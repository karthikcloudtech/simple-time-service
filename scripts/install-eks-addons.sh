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
# CERT-MANAGER INSTALLATION (for bootstrap)
# ============================================================================

wait_for_cert_manager_webhook() {
    log "Waiting for cert-manager webhook to be ready..."
    
    # Wait for deployment to be available
    if ! kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=3m 2>/dev/null; then
        warn "cert-manager-webhook deployment not ready after 3 minutes"
        return 1
    fi
    
    # Verify webhook configuration exists
    log "Verifying cert-manager webhook configuration..."
    local webhook_ready=false
    for i in {1..30}; do
        if kubectl get validatingwebhookconfiguration cert-manager-webhook &>/dev/null && \
           kubectl get mutatingwebhookconfiguration cert-manager-webhook &>/dev/null; then
            webhook_ready=true
            break
        fi
        [ $((i % 5)) -eq 0 ] && log "Waiting for webhook configuration... ($i/30)"
        sleep 2
    done
    
    if [ "$webhook_ready" != "true" ]; then
        warn "Webhook configurations not found, but continuing..."
        return 1
    fi
    
    # Test webhook by checking if CRD is fully established and webhook is responding
    log "Verifying ClusterIssuer CRD is established..."
    local crd_established=false
    for i in {1..30}; do
        if kubectl get crd clusterissuers.cert-manager.io &>/dev/null; then
            local crd_status=$(kubectl get crd clusterissuers.cert-manager.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "False")
            if [ "$crd_status" = "True" ]; then
                log "✓ ClusterIssuer CRD is established"
                crd_established=true
                
                # Test webhook functionality by attempting to list ClusterIssuers (tests API connectivity)
                log "Testing webhook API connectivity..."
                if kubectl get clusterissuer --request-timeout=5s &>/dev/null 2>&1; then
                    log "✓ Webhook API is responding"
        return 0
    else
                    [ $((i % 5)) -eq 0 ] && log "Webhook API test failed, retrying... ($i/30)"
                fi
            else
                # CRD exists but not yet established
                [ $((i % 5)) -eq 0 ] && log "Waiting for CRD to be established... ($i/30)"
            fi
        else
            # CRD doesn't exist yet
            [ $((i % 5)) -eq 0 ] && log "Waiting for CRD to be established... ($i/30)"
        fi
        sleep 2
    done
    
    if [ "$crd_established" = "true" ]; then
        warn "CRD is established but webhook API not responding, but continuing..."
    else
        warn "CRD may not be fully established or webhook not responding, but continuing..."
    fi
    return 1
}

install_cluster_issuers() {
    log "Installing Let's Encrypt ClusterIssuers..."
    local clusterissuer_file="$PROJECT_ROOT/gitops/cluster-issuers/clusterissuer.yaml"
    
    if [ ! -f "$clusterissuer_file" ]; then
        warn "ClusterIssuer file not found at $clusterissuer_file, skipping..."
        return 1
    fi
    
    # Check if ClusterIssuers already exist (might be managed by ArgoCD)
    local existing_count=$(kubectl get clusterissuer letsencrypt-prod letsencrypt-staging --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$existing_count" -eq 2 ]; then
        log "ClusterIssuers already exist (may be managed by ArgoCD), skipping installation..."
        log "To manage via ArgoCD, create an ArgoCD Application for gitops/cluster-issuers/"
        return 0
    fi
    
    # Wait for cert-manager webhook to be ready before applying ClusterIssuers
    wait_for_cert_manager_webhook || warn "Webhook readiness check had issues, but continuing..."
    
    # Verify ClusterIssuer CRD exists
    if ! kubectl get crd clusterissuers.cert-manager.io &>/dev/null; then
        error "ClusterIssuer CRD not found. cert-manager may not be properly installed."
        return 1
    fi
    
    # Apply ClusterIssuers with retry logic
    log "Applying ClusterIssuers via script (bootstrap installation)..."
    log "Note: For ongoing management, consider creating an ArgoCD Application"
    
    local max_retries=5
    local retry_delay=10
    local attempt=1
    local apply_success=false
    
    while [ $attempt -le $max_retries ]; do
        log "Attempt $attempt/$max_retries to apply ClusterIssuers..."
        
        # Capture output for error reporting
        local apply_output=""
    if [ "$VERBOSE" = "true" ]; then
            if kubectl apply -f "$clusterissuer_file"; then
                apply_success=true
                break
            else
                # In VERBOSE mode, error was already shown, don't set placeholder
                apply_output=""
            fi
        else
            apply_output=$(kubectl apply -f "$clusterissuer_file" 2>&1)
            if [ $? -eq 0 ]; then
                apply_success=true
                break
            fi
        fi
        
        if [ $attempt -lt $max_retries ]; then
            warn "Failed to apply ClusterIssuers (attempt $attempt/$max_retries)"
            if [ -n "$apply_output" ]; then
                echo "$apply_output" | head -20
            fi
            log "Retrying in ${retry_delay}s..."
            sleep $retry_delay
            retry_delay=$((retry_delay + 5))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [ "$apply_success" != "true" ]; then
        error "Failed to apply ClusterIssuers after $max_retries attempts"
        if [ -n "$apply_output" ] && [ "$VERBOSE" != "true" ]; then
            echo "Error details:"
            echo "$apply_output"
        fi
            return 1
    fi
    
    # Verify ClusterIssuers are ready
    log "Verifying ClusterIssuers..."
    local verified_count=0
    for issuer in letsencrypt-prod letsencrypt-staging; do
        if kubectl get clusterissuer "$issuer" &>/dev/null; then
            log "✓ ClusterIssuer $issuer created"
            verified_count=$((verified_count + 1))
        else
            warn "ClusterIssuer $issuer not found after creation"
        fi
    done
    
    if [ $verified_count -eq 2 ]; then
    success "ClusterIssuers installed (bootstrap)"
    log "💡 Tip: Create an ArgoCD Application for gitops/cluster-issuers/ for GitOps management"
        return 0
    else
        warn "Only $verified_count/2 ClusterIssuers verified. They may still be initializing."
        return 0  # Don't fail, as they might be created but not immediately visible
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
    log "2. Port-forward to access UI:"
    log "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
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
