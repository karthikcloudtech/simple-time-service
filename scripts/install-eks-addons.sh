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
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============================================================================
# PREREQUISITES
# ============================================================================

check_prerequisites() {
    for cmd in kubectl aws; do
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
            log "Configure DNS: Create CNAME record for argocd.trainerkarthik.shop pointing to $ALB_HOSTNAME"
        else
            log "ALB is being created. Check status with: kubectl get ingress argocd-ingress -n argocd"
        fi
    else
        warn "Failed to apply ArgoCD ingress. You may need to apply it manually:"
        warn "  kubectl apply -k gitops/argocd/"
        warn "Note: AWS Load Balancer Controller must be running for ingress to work"
    fi
    
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
    log "     https://argocd.trainerkarthik.shop"
    log "   Option B - Port-forward:"
    log "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log ""
    log "3. Ensure IAM roles are created (via Terraform):"
    log "   cd infra/environments/prod && terraform apply"
    log ""
    log "4. Annotate ServiceAccounts with IAM role ARNs (if not done by Terraform):"
    log "   # Get role ARNs from Terraform outputs:"
    log "   terraform output aws_load_balancer_controller_role_arn"
    log "   terraform output cluster_autoscaler_role_arn"
    log "   terraform output cert_manager_role_arn"
    log ""
    log "   # Annotate ServiceAccounts:"
    log "   kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \\"
    log "     eks.amazonaws.com/role-arn=<ROLE_ARN>"
    log "   kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler -n kube-system \\"
    log "     eks.amazonaws.com/role-arn=<ROLE_ARN>"
    log "   kubectl annotate serviceaccount cert-manager -n cert-manager \\"
    log "     eks.amazonaws.com/role-arn=<ROLE_ARN>"
    log ""
    log "5. Apply ArgoCD Applications (ArgoCD will manage all addons):"
    log "   kubectl apply -f gitops/argo-apps/*.yaml"
    log ""
    log "6. ArgoCD will automatically sync and manage all addons via GitOps"
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
    
    install_argocd_bootstrap
    
    log ""
    success "Bootstrap completed! ArgoCD will manage all addons via GitOps."
    log ""
    log "To apply ArgoCD Applications:"
    log "  kubectl apply -f gitops/argo-apps/*.yaml"
}

main "$@"
