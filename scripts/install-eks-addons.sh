#!/bin/bash
# EKS Addons Installation Script
# 
# PRIMARY MODE (GitOps): Bootstraps ArgoCD, which then manages all addons via GitOps
# 
# All addons are now managed via ArgoCD Applications:
#   - gitops/argo-apps/*.yaml (ArgoCD Application manifests)
#   - gitops/helm-charts/*/values.yaml (Helm values)
#
# IAM roles are created by Terraform (infra/terraform/modules/eks/iam_roles.tf)
# See gitops/argo-apps/README.md for details on ArgoCD Applications

set -uo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Verbose output
VERBOSE="${VERBOSE:-false}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================================
# UTILITIES
# ============================================================================

log() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_warn() { echo "[WARN] $1"; }
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============================================================================
# PREREQUISITES
# ============================================================================

check_prerequisites() {
    for cmd in kubectl aws helm; do
        command -v "$cmd" &>/dev/null || error "$cmd not found. Please install it first."
    done
}

verify_setup() {
    log "Verifying AWS credentials..."
    aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured"
    
    log "Verifying cluster connection..."
    if ! kubectl cluster-info &>/dev/null 2>&1; then
        log "Updating kubeconfig..."
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || \
            error "Failed to connect to cluster $CLUSTER_NAME"
    fi
}

wait_for_nodes() {
    log "Waiting for EKS nodes to be ready..."
    for i in {1..60}; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)
        if [ "$ready_nodes" -gt 0 ]; then
            log "Found $ready_nodes ready node(s)"
            return 0
        fi
        [ $((i % 5)) -eq 0 ] && log "Waiting for nodes... ($i/60)"
        sleep 10
    done
    error "Timeout waiting for nodes to be ready"
}

# ============================================================================
# INSTALL AWS LOAD BALANCER CONTROLLER
# ============================================================================

install_aws_load_balancer_controller() {
    log "Installing AWS Load Balancer Controller via Helm..."
    
    # Check if already installed
    if helm list -n kube-system | grep -q aws-load-balancer-controller; then
        log "AWS Load Balancer Controller is already installed, skipping..."
        return 0
    fi
    
    # Get VPC ID and IAM role ARN from Terraform or environment variables
    local terraform_dir="${TERRAFORM_DIR:-infra/environments/prod}"
    local original_dir=$(pwd)
    local vpc_id="${VPC_ID:-}"
    local alb_role_arn="${AWS_LOAD_BALANCER_CONTROLLER_ROLE_ARN:-}"
    
    # Try to get from Terraform if not set via environment variables
    if [ -z "$vpc_id" ] || [ -z "$alb_role_arn" ]; then
        if [ -d "$terraform_dir" ] && command -v terraform &>/dev/null; then
            cd "$terraform_dir" || {
                log_warn "Could not access Terraform directory: $terraform_dir"
                return 1
            }
            
            # Get VPC ID - try VPC name first, then EKS cluster
            if [ -z "$vpc_id" ]; then
                local project_name=$(terraform output -raw project_name 2>/dev/null || \
                    echo "${CLUSTER_NAME%-prod}" | sed 's/-prod$//')
                local environment=$(terraform output -raw environment 2>/dev/null || \
                    echo "${CLUSTER_NAME##*-}" | sed 's/^.*-//')
                # Try environment-specific VPC name first, then fallback to non-environment-specific
                local vpc_name="${project_name}-vpc-${environment}"
                
                log "Fetching VPC ID by name: $vpc_name..."
                vpc_id=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
                    --filters "Name=tag:Name,Values=$vpc_name" \
                    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
                
                # Fallback to non-environment-specific VPC name if not found
                if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
                    local vpc_name_fallback="${project_name}-vpc"
                    log "VPC not found with environment suffix, trying: $vpc_name_fallback..."
                    vpc_id=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
                        --filters "Name=tag:Name,Values=$vpc_name_fallback" \
                        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
                fi
                
                if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
                    log "VPC not found by name, trying EKS cluster..."
                    vpc_id=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
                        --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")
                fi
            fi
            
            # Get IAM role ARN
            if [ -z "$alb_role_arn" ]; then
                alb_role_arn=$(terraform output -raw aws_load_balancer_controller_role_arn 2>/dev/null || echo "")
            fi
            
            cd "$original_dir" || true
        fi
    fi
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        error "Could not retrieve VPC ID. Set VPC_ID environment variable or ensure Terraform outputs are available."
    fi
    
    if [ -z "$alb_role_arn" ]; then
        error "Could not retrieve AWS Load Balancer Controller IAM role ARN. Set AWS_LOAD_BALANCER_CONTROLLER_ROLE_ARN environment variable or ensure Terraform outputs are available."
    fi
    
    log "VPC ID: $vpc_id"
    log "IAM Role ARN: $alb_role_arn"
    
    # Ensure ServiceAccount exists with IAM role annotation
    log "Creating/updating ServiceAccount..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $alb_role_arn
EOF
    
    # Add EKS Helm repo if not already added
    if ! helm repo list | grep -q eks; then
        log "Adding EKS Helm repository..."
        helm repo add eks https://aws.github.io/eks-charts || error "Failed to add EKS Helm repository"
        helm repo update || error "Failed to update Helm repositories"
    fi
    
    # Install AWS Load Balancer Controller via Helm
    log "Installing AWS Load Balancer Controller Helm chart..."
    if helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region="$AWS_REGION" \
        --set vpcId="$vpc_id" \
        --set enableServiceMutatorWebhook=false \
        --wait \
        --timeout 5m; then
        log_success "AWS Load Balancer Controller installed successfully"
    else
        error "Failed to install AWS Load Balancer Controller"
    fi
    
    # Wait for controller to be ready
    log "Waiting for AWS Load Balancer Controller to be ready..."
    kubectl wait --for=condition=available deployment/aws-load-balancer-controller -n kube-system --timeout=5m || \
        log_warn "AWS Load Balancer Controller may still be starting"
}

# ============================================================================
# UPDATE SERVICEACCOUNT ANNOTATIONS
# ============================================================================

update_serviceaccount_annotations() {
    log "Updating ServiceAccount YAML files with IAM role ARNs from Terraform..."
    
    # Check if Terraform outputs are available (if running from Terraform)
    local terraform_dir="${TERRAFORM_DIR:-infra/environments/prod}"
    local original_dir=$(pwd)
    
    if [ -d "$terraform_dir" ] && command -v terraform &>/dev/null; then
        log "Fetching IAM role ARNs from Terraform outputs..."
        cd "$terraform_dir" || {
            log_warn "Could not access Terraform directory: $terraform_dir"
            log_warn "ServiceAccount annotations will need to be updated manually"
            return 1
        }
        
        # Get role ARNs from Terraform
        local alb_role_arn=$(terraform output -raw aws_load_balancer_controller_role_arn 2>/dev/null || echo "")
        local autoscaler_role_arn=$(terraform output -raw cluster_autoscaler_role_arn 2>/dev/null || echo "")
        local cert_manager_role_arn=$(terraform output -raw cert_manager_role_arn 2>/dev/null || echo "")
        
        # Get VPC ID - try multiple methods (VPC name, then EKS cluster)
        local vpc_id=""
        if command -v aws &>/dev/null; then
            # Method 1: Get VPC ID by VPC name/tag (preferred - more explicit)
            # VPC name format: <project-name>-vpc-<environment> (e.g., simple-time-service-vpc-prod)
            local project_name=$(terraform output -raw project_name 2>/dev/null || \
                echo "${CLUSTER_NAME%-prod}" | sed 's/-prod$//')
            local environment=$(terraform output -raw environment 2>/dev/null || \
                echo "${CLUSTER_NAME##*-}" | sed 's/^.*-//')
            # Try environment-specific VPC name first
            local vpc_name="${project_name}-vpc-${environment}"
            
            log "Fetching VPC ID by name: $vpc_name..."
            vpc_id=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
                --filters "Name=tag:Name,Values=$vpc_name" \
                --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
            
            # Fallback to non-environment-specific VPC name if not found
            if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
                local vpc_name_fallback="${project_name}-vpc"
                log "VPC not found with environment suffix, trying: $vpc_name_fallback..."
                vpc_id=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
                    --filters "Name=tag:Name,Values=$vpc_name_fallback" \
                    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
            fi
            
            if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ]; then
                log_success "Retrieved VPC ID by name ($vpc_name): $vpc_id"
            else
                # Method 2: Fallback to EKS cluster describe
                log "VPC not found by name, trying EKS cluster..."
                vpc_id=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
                    --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")
                if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
                    log_success "Retrieved VPC ID from EKS cluster: $vpc_id"
                else
                    log_warn "Could not retrieve VPC ID (tried VPC name and EKS cluster)"
                fi
            fi
        fi
        
        # Restore original directory
        cd "$original_dir" || {
            log_warn "Could not restore original directory, continuing from Terraform directory"
        }
        
        # Update YAML files with actual role ARNs (so ArgoCD syncs correct values)
        local sa_dir="$PROJECT_ROOT/gitops/serviceaccounts"
        local yaml_updated=0
        
        if [ -n "$alb_role_arn" ] && [ -f "$sa_dir/aws-load-balancer-controller-sa.yaml" ]; then
            log "Updating AWS Load Balancer Controller ServiceAccount YAML..."
            # Replace any existing ARN or placeholder with actual ARN
            # Pattern matches: arn:aws:iam::[0-9]*:role/... or arn:aws:iam::ACCOUNT_ID:role/...
            if sed -i.bak "s|arn:aws:iam::[0-9A-Z_]*:role/simple-time-service-aws-load-balancer-controller-role|$alb_role_arn|g" \
                "$sa_dir/aws-load-balancer-controller-sa.yaml" 2>/dev/null; then
                rm -f "$sa_dir/aws-load-balancer-controller-sa.yaml.bak"
                log_success "Updated AWS Load Balancer Controller ServiceAccount YAML"
                yaml_updated=1
            fi
        fi
        
        if [ -n "$autoscaler_role_arn" ] && [ -f "$sa_dir/cluster-autoscaler-sa.yaml" ]; then
            log "Updating Cluster Autoscaler ServiceAccount YAML..."
            # Replace any existing ARN or placeholder with actual ARN
            if sed -i.bak "s|arn:aws:iam::[0-9A-Z_]*:role/simple-time-service-cluster-autoscaler-role|$autoscaler_role_arn|g" \
                "$sa_dir/cluster-autoscaler-sa.yaml" 2>/dev/null; then
                rm -f "$sa_dir/cluster-autoscaler-sa.yaml.bak"
                log_success "Updated Cluster Autoscaler ServiceAccount YAML"
                yaml_updated=1
            fi
        fi
        
        if [ -n "$cert_manager_role_arn" ] && [ -f "$sa_dir/cert-manager-sa.yaml" ]; then
            log "Updating Cert-Manager ServiceAccount YAML..."
            # Replace any existing ARN or placeholder with actual ARN
            if sed -i.bak "s|arn:aws:iam::[0-9A-Z_]*:role/simple-time-service-cert-manager-role|$cert_manager_role_arn|g" \
                "$sa_dir/cert-manager-sa.yaml" 2>/dev/null; then
                rm -f "$sa_dir/cert-manager-sa.yaml.bak"
                log_success "Updated Cert-Manager ServiceAccount YAML"
                yaml_updated=1
            fi
        fi
        
        # Note: AWS Load Balancer Controller is installed directly via Helm (not via ArgoCD)
        # This is because it needs VPC ID which cannot be set via VPC name in Helm chart
        
        if [ $yaml_updated -eq 1 ]; then
            log_success "ServiceAccount YAML files updated with IAM role ARNs"
            log "Note: Commit these changes to Git so ArgoCD maintains correct values"
        fi
        
        # Apply ServiceAccounts directly to Kubernetes
        log "Applying ServiceAccounts..."
        if [ -d "$sa_dir" ]; then
            kubectl apply -k "$sa_dir" &>/dev/null && \
                log_success "ServiceAccounts applied" || \
                log_warn "Some ServiceAccounts may have failed to apply"
        fi
        
        # Annotate cluster-autoscaler ServiceAccount (created by Helm, needs manual annotation)
        if [ -n "$autoscaler_role_arn" ]; then
            kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler \
                -n kube-system eks.amazonaws.com/role-arn="$autoscaler_role_arn" \
                --overwrite &>/dev/null 2>&1 && \
                log_success "Cluster Autoscaler annotated" || \
                log "Cluster Autoscaler ServiceAccount not yet created"
        fi
    else
        log_warn "Terraform directory not found or terraform not available"
        log_warn "ServiceAccounts will be created by ArgoCD, but IAM annotations may be missing"
        log_warn "Update gitops/serviceaccounts/*.yaml with actual role ARNs and sync via ArgoCD"
    fi
}

# ============================================================================
# APPLY ARGOCD APPLICATIONS
# ============================================================================

apply_argocd_applications() {
    log "Applying ArgoCD Applications..."
    
    local apps_dir="$PROJECT_ROOT/gitops/argo-apps"
    
    if [ ! -d "$apps_dir" ]; then
        log_warn "ArgoCD applications directory not found: $apps_dir"
        return 1
    fi
    
    # Wait a bit for ArgoCD to be fully ready
    log "Waiting for ArgoCD to be ready..."
    sleep 5
    
    # Apply all ArgoCD Application manifests (idempotent)
    # Note: AWS Load Balancer Controller is installed directly via Helm (not via ArgoCD)
    log "Applying ArgoCD Application manifests..."
    local applied=0
    local failed=0
    
    for app_file in "$apps_dir"/*.yaml; do
        if [ -f "$app_file" ]; then
            local app_name=$(basename "$app_file" .yaml)
            if kubectl apply -f "$app_file" &>/dev/null; then
                log_success "Applied: $app_name"
                applied=$((applied + 1))
            else
                log_warn "Failed to apply: $app_name"
                failed=$((failed + 1))
            fi
        fi
    done
    
    if [ $applied -gt 0 ]; then
        log_success "Applied $applied ArgoCD Application(s)"
        log "ArgoCD will now manage all addons via GitOps"
    fi
    
    if [ $failed -gt 0 ]; then
        log_warn "$failed Application(s) failed to apply (may already exist)"
        log_warn "Check with: kubectl get applications -n argocd"
    fi
}

# ============================================================================
# ARGOCD BOOTSTRAP
# ============================================================================

install_argocd_bootstrap() {
    # Check if ArgoCD is already installed
    if kubectl get deployment argocd-server -n argocd &>/dev/null 2>&1; then
        log "ArgoCD is already installed, skipping bootstrap..."
        return 0
    fi
    
    log "Bootstrapping ArgoCD (GitOps mode)..."
    log "After ArgoCD is installed, it will manage all addons via GitOps"
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Install ArgoCD from official manifest
    log "Installing ArgoCD from official manifest..."
    if [ "$VERBOSE" = "true" ]; then
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    else
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml &>/dev/null
    fi
    
    # Wait for ArgoCD server to be available
    log "Waiting for ArgoCD server to be ready (this may take a few minutes)..."
    if kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=10m &>/dev/null; then
        success "ArgoCD bootstrap completed!"
    else
        warn "ArgoCD server may still be starting. Check with: kubectl get pods -n argocd"
        return 1
    fi
    
    # Apply ArgoCD ingress (requires AWS Load Balancer Controller to be running)
    log "Applying ArgoCD ingress..."
    if kubectl apply -k "$PROJECT_ROOT/gitops/argocd/" &>/dev/null; then
        log "ArgoCD ingress applied successfully"
        log "Waiting for ingress to be created (this may take a minute)..."
        sleep 10
        ALB_HOSTNAME=$(kubectl get ingress argocd-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$ALB_HOSTNAME" ]; then
            log "ALB created: $ALB_HOSTNAME"
            log "Configure DNS: Create CNAME record for argocd.kart24.shop pointing to $ALB_HOSTNAME"
        else
            log "ALB is being created. Check status with: kubectl get ingress argocd-ingress -n argocd"
        fi
    else
        warn "Failed to apply ArgoCD ingress. You may need to apply it manually:"
        warn "  kubectl apply -k gitops/argocd/"
        warn "Note: AWS Load Balancer Controller must be running for ingress to work"
    fi
    
    # Update ServiceAccounts with IAM role ARNs from Terraform outputs
    # Also updates VPC ID dynamically (by VPC name or EKS cluster)
    update_serviceaccount_annotations
    
    # Apply ArgoCD Applications (ArgoCD will manage all addons)
    apply_argocd_applications
    
    # Show next steps
    log ""
    log "═══════════════════════════════════════════════════════════════"
    log "Next Steps:"
    log "═══════════════════════════════════════════════════════════════"
    log ""
    log "1. Get ArgoCD admin password:"
    log "   kubectl -n argocd get secret argocd-initial-admin-secret \\"
    log "     -o jsonpath=\"{.data.password}\" | base64 -d"
    log ""
    log "2. Access ArgoCD UI:"
    log "   Option A - Via Ingress (if DNS configured):"
    log "     https://argocd.kart24.shop"
    log "   Option B - Port-forward:"
    log "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log ""
    log "3. Monitor ArgoCD Applications:"
    log "   kubectl get applications -n argocd"
    log "   argocd app list"
    log ""
    log "4. ArgoCD will automatically sync and manage all addons via GitOps"
    log ""
    log "See gitops/argo-apps/README.md for details on ArgoCD Applications"
    log "═══════════════════════════════════════════════════════════════"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log "═══════════════════════════════════════════════════════════════"
    log "EKS Addons Installation - ArgoCD Bootstrap"
    log "Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
    log "═══════════════════════════════════════════════════════════════"
    log ""
    log "This script bootstraps ArgoCD only."
    log "All addons are managed via ArgoCD GitOps (gitops/argo-apps/)"
    log ""
    [ "$VERBOSE" = "true" ] && log "Verbose mode enabled"
    
    check_prerequisites
    verify_setup
    wait_for_nodes
    
    # Install AWS Load Balancer Controller first (required for ArgoCD ingress)
    install_aws_load_balancer_controller
    
    install_argocd_bootstrap
    
    log ""
    success "Bootstrap completed! ArgoCD will manage all addons via GitOps."
    log ""
    log "To apply ArgoCD Applications:"
    log "  kubectl apply -f gitops/argo-apps/*.yaml"
}

main "$@"

