#!/bin/bash
# Bootstrap script for EKS addons - Minimal installation for ArgoCD bootstrap
# After ArgoCD is installed, all other addons are managed via GitOps
# See gitops/argo-apps/ for ArgoCD Application manifests

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log() { echo "[INFO] $1"; }
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

check_prerequisites() {
    for cmd in kubectl aws; do
        command -v "$cmd" &>/dev/null || error "$cmd not found"
    done
}

verify_setup() {
    aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured"
    kubectl cluster-info &>/dev/null 2>&1 || aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || error "Failed to connect"
}

wait_for_nodes() {
    log "Waiting for EKS nodes to be ready..."
    for i in {1..60}; do
        [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)" -gt 0 ] && return 0
        [ $((i % 5)) -eq 0 ] && log "Waiting for nodes... ($i/60)"
        sleep 10
    done
    error "Timeout waiting for nodes"
}

install_argocd_bootstrap() {
    # Check if ArgoCD is already installed
    if kubectl get deployment argocd-server -n argocd &>/dev/null 2>&1; then
        log "ArgoCD is already installed, skipping bootstrap..."
        return 0
    fi
    
    log "Bootstrapping ArgoCD (minimal installation)..."
    log "After ArgoCD is installed, it will manage itself and all other addons via GitOps"
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Install ArgoCD from official manifest
    # NOTE: This is a one-time bootstrap. After installation, ArgoCD manages itself via gitops/argo-apps/argocd.yaml
    log "Installing ArgoCD from official manifest..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD server to be available
    log "Waiting for ArgoCD server to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=10m &>/dev/null || {
        warn "ArgoCD server may still be starting. Check with: kubectl get pods -n argocd"
        return 1
    }
    
    success "ArgoCD bootstrap completed!"
    log ""
    log "Next steps:"
    log "1. Get ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    log "2. Port-forward to access UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log "3. Apply ArgoCD Applications: kubectl apply -f gitops/argo-apps/*.yaml"
    log "4. ArgoCD will then manage all addons via GitOps"
    log ""
    log "See gitops/argo-apps/README.md for details on ArgoCD Applications"
}

main() {
    log "EKS Addons Bootstrap - Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
    log "This script only installs ArgoCD. All other addons are managed via GitOps."
    log ""
    
    check_prerequisites
    verify_setup
    wait_for_nodes
    
    install_argocd_bootstrap
    
    success "Bootstrap completed! ArgoCD is now managing all addons via GitOps."
}

main "$@"

