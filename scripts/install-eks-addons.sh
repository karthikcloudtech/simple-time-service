#!/bin/bash
set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-simple-time-service}"

INSTALL_ALB_CONTROLLER="${INSTALL_ALB_CONTROLLER:-true}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"
INSTALL_METRICS_SERVER="${INSTALL_METRICS_SERVER:-true}"
INSTALL_CLUSTER_AUTOSCALER="${INSTALL_CLUSTER_AUTOSCALER:-false}"
INSTALL_CERT_MANAGER="${INSTALL_CERT_MANAGER:-true}"
INSTALL_PROMETHEUS="${INSTALL_PROMETHEUS:-true}"
INSTALL_EFK="${INSTALL_EFK:-true}"
INSTALL_OTEL_COLLECTOR="${INSTALL_OTEL_COLLECTOR:-true}"

# Optional: Set VERBOSE=true to show all command output
VERBOSE="${VERBOSE:-false}"

# Get script directory to find storage class file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STORAGE_CLASS_FILE="$PROJECT_ROOT/k8s/storage-class-gp3.yaml"

log() { echo "[INFO] $1"; }
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

check_prerequisites() {
    for cmd in kubectl helm aws jq; do
        command -v "$cmd" &>/dev/null || error "$cmd not found"
    done
}

verify_setup() {
    aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured"
    kubectl cluster-info &>/dev/null 2>&1 || aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || error "Failed to connect"
}

wait_for_nodes() {
    for i in {1..60}; do
        [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)" -gt 0 ] && return 0
        [ $((i % 5)) -eq 0 ] && log "Waiting for nodes... ($i/60)"
        sleep 10
    done
    error "Timeout waiting for nodes"
}

wait_for_elasticsearch() {
    log "Waiting for Elasticsearch to be ready (max 5 minutes)..."
    for i in {1..30}; do
        if kubectl get pods -n logging -l app=elasticsearch-master --no-headers 2>/dev/null | grep -q "Running\|Completed"; then
            local ready_pods=$(kubectl get pods -n logging -l app=elasticsearch-master --no-headers 2>/dev/null | grep -c "Running\|Completed" || echo 0)
            if [ "$ready_pods" -gt 0 ]; then
                log "Elasticsearch is ready! ($ready_pods pod(s) running)"
                return 0
            fi
        fi
        [ $((i % 3)) -eq 0 ] && log "Waiting for Elasticsearch... ($((i*10))s/300s)"
        sleep 10
    done
    warn "Elasticsearch may still be starting. Continuing with other components..."
}

helm_repo() {
    helm repo add "$1" "$2" &>/dev/null || true
    helm repo update "$1" &>/dev/null
}

ns() {
    kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
}

install_alb_controller() {
    [ "$INSTALL_ALB_CONTROLLER" != "true" ] && return
    helm list -n kube-system | grep -q aws-load-balancer-controller && return
    log "Installing AWS Load Balancer Controller..."
    
    local oidc_issuer=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
    [ -z "$oidc_issuer" ] || [ "$oidc_issuer" == "None" ] && error "OIDC issuer not found"
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_name="${PROJECT_NAME}-aws-load-balancer-controller-policy"
    local role_name="${PROJECT_NAME}-aws-load-balancer-controller-role"
    
    if ! aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$oidc_issuer')].Arn" --output text | grep -q .; then
        local thumbprint=$(openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d'=' -f2 | tr -d ':')
        aws iam create-open-id-connect-provider --url "https://${oidc_issuer}" --client-id-list "sts.amazonaws.com" --thumbprint-list "$thumbprint" 2>/dev/null || true
    fi
    
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${account_id}:policy/${policy_name}" &>/dev/null; then
        # Use local IAM policy file with all required permissions including DescribeListenerAttributes
        local policy_file="$SCRIPT_DIR/aws-load-balancer-controller-iam-policy.json"
        if [ -f "$policy_file" ]; then
            aws iam create-policy --policy-name "$policy_name" --policy-document file://"$policy_file" &>/dev/null
        else
            # Fallback to downloading from GitHub if local file doesn't exist
            curl -s -o /tmp/alb-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json
            aws iam create-policy --policy-name "$policy_name" --policy-document file:///tmp/alb-policy.json &>/dev/null
            rm -f /tmp/alb-policy.json
        fi
    else
        # Update existing policy with latest permissions
        local policy_file="$SCRIPT_DIR/aws-load-balancer-controller-iam-policy.json"
        if [ -f "$policy_file" ]; then
            local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
            aws iam create-policy-version --policy-arn "$policy_arn" --policy-document file://"$policy_file" --set-as-default &>/dev/null || true
        fi
    fi
    
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
    cat > /tmp/trust-policy.json <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::${account_id}:oidc-provider/${oidc_issuer}"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"${oidc_issuer}:sub":"system:serviceaccount:kube-system:aws-load-balancer-controller","${oidc_issuer}:aud":"sts.amazonaws.com"}}}]}
EOF
    
    if ! aws iam get-role --role-name "$role_name" &>/dev/null; then
        aws iam create-role --role-name "$role_name" --assume-role-policy-document file:///tmp/trust-policy.json &>/dev/null
    else
        aws iam update-assume-role-policy --role-name "$role_name" --policy-document file:///tmp/trust-policy.json &>/dev/null
    fi
    aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" &>/dev/null || true
    rm -f /tmp/trust-policy.json
    
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
    helm_repo eks https://aws.github.io/eks-charts
    ns kube-system
    kubectl create serviceaccount aws-load-balancer-controller -n kube-system --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
    
    local vpc_id=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)
    local helm_args=("--set" "clusterName=$CLUSTER_NAME" "--set" "serviceAccount.create=false" "--set" "serviceAccount.name=aws-load-balancer-controller" "--set" "region=$AWS_REGION" "--set" "enableServiceMutatorWebhook=false")
    [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ] && helm_args+=("--set" "vpcId=$vpc_id")
    
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system "${helm_args[@]}" --wait --timeout 5m
    else
        helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system "${helm_args[@]}" --wait --timeout 5m &>/dev/null
    fi
    success "AWS Load Balancer Controller installed"
}

install_metrics_server() {
    [ "$INSTALL_METRICS_SERVER" != "true" ] && return
    helm list -n kube-system | grep -q metrics-server && return
    log "Installing Metrics Server..."
    helm_repo metrics-server https://kubernetes-sigs.github.io/metrics-server/
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --set args="{--kubelet-insecure-tls}" --wait --timeout 3m
    else
        helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --set args="{--kubelet-insecure-tls}" --wait --timeout 3m &>/dev/null
    fi
    success "Metrics Server installed"
}

install_argocd() {
    [ "$INSTALL_ARGOCD" != "true" ] && return
    kubectl get deployment argocd-server -n argocd &>/dev/null 2>&1 && return
    log "Installing ArgoCD..."
    ns argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=5m &>/dev/null
    success "ArgoCD installed"
}

verify_cert_manager_rbac() {
    log "Verifying cert-manager Kubernetes RBAC..."
    local issues=0
    
    # Check service account exists
    if ! kubectl get serviceaccount cert-manager -n cert-manager &>/dev/null; then
        error "cert-manager service account not found"
        return 1
    fi
    
    # Check ClusterRole exists
    if ! kubectl get clusterrole cert-manager-controller &>/dev/null; then
        warn "cert-manager-controller ClusterRole not found"
        ((issues++))
    fi
    
    # Check ClusterRoleBinding exists
    if ! kubectl get clusterrolebinding cert-manager-controller &>/dev/null; then
        warn "cert-manager-controller ClusterRoleBinding not found"
        ((issues++))
    fi
    
    # Check Role exists in cert-manager namespace
    if ! kubectl get role cert-manager:leaderelection -n cert-manager &>/dev/null; then
        warn "cert-manager:leaderelection Role not found"
        ((issues++))
    fi
    
    # Check RoleBinding exists in cert-manager namespace
    if ! kubectl get rolebinding cert-manager:leaderelection -n cert-manager &>/dev/null; then
        warn "cert-manager:leaderelection RoleBinding not found"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        log "✓ Kubernetes RBAC verified"
        return 0
    else
        warn "Found $issues RBAC issues - cert-manager Helm chart should create these automatically"
        return 1
    fi
}

configure_cert_manager_iam() {
    log "Configuring cert-manager IAM role annotation..."
    local cert_manager_role_arn="${CERT_MANAGER_ROLE_ARN:-}"
    
    # Try to get from Terraform output if not set
    if [ -z "$cert_manager_role_arn" ]; then
        if command -v terraform &>/dev/null; then
            cert_manager_role_arn=$(terraform -chdir="$PROJECT_ROOT/infra/environments/prod" output -raw cert_manager_role_arn 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$cert_manager_role_arn" ]; then
        warn "CERT_MANAGER_ROLE_ARN not set and could not get from Terraform output."
        warn "Cert-manager will not be able to use Route53 DNS-01 challenge."
        warn "Set CERT_MANAGER_ROLE_ARN environment variable or run: terraform output cert_manager_role_arn"
        return 1
    fi
    
    # Check current annotation
    local current_arn=$(kubectl get serviceaccount cert-manager -n cert-manager -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    
    if [ "$current_arn" = "$cert_manager_role_arn" ]; then
        log "✓ IAM role annotation already correct: $cert_manager_role_arn"
        return 0
    fi
    
    # Annotate service account
    log "Annotating cert-manager service account with IAM role ARN: $cert_manager_role_arn"
    if kubectl annotate serviceaccount cert-manager -n cert-manager \
      eks.amazonaws.com/role-arn="$cert_manager_role_arn" \
      --overwrite &>/dev/null; then
        log "✓ Service account annotated successfully"
        
        # Restart cert-manager pods to pick up the new IAM role
        log "Restarting cert-manager pods to apply IAM role..."
        kubectl rollout restart deployment cert-manager -n cert-manager &>/dev/null || true
        kubectl rollout restart deployment cert-manager-webhook -n cert-manager &>/dev/null || true
        kubectl rollout restart deployment cert-manager-cainjector -n cert-manager &>/dev/null || true
        
        # Wait for pods to be ready
        log "Waiting for cert-manager pods to be ready..."
        kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=2m &>/dev/null || true
        return 0
    else
        error "Failed to annotate cert-manager service account"
        return 1
    fi
}

install_cert_manager() {
    [ "$INSTALL_CERT_MANAGER" != "true" ] && return
    
    # Check if already installed
    if helm list -n cert-manager | grep -q cert-manager; then
        log "Cert-Manager already installed, verifying configuration..."
        verify_cert_manager_rbac || true
        configure_cert_manager_iam || true
        install_cluster_issuers || true
        return
    fi
    
    log "Installing Cert-Manager..."
    helm_repo jetstack https://charts.jetstack.io
    ns cert-manager
    
    # Install CRDs
    log "Installing cert-manager CRDs..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml &>/dev/null
    
    # Install cert-manager
    log "Installing cert-manager Helm chart..."
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --set installCRDs=false --wait --timeout 5m
    else
        helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --set installCRDs=false --wait --timeout 5m &>/dev/null
    fi
    
    # Wait for deployments to be available
    log "Waiting for cert-manager deployments..."
    kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-cainjector -n cert-manager --timeout=5m &>/dev/null
    
    # Verify RBAC
    verify_cert_manager_rbac || warn "Some RBAC resources missing, but continuing..."
    
    # Configure IAM role
    configure_cert_manager_iam || warn "IAM role configuration failed, cert-manager may not have Route53 access"
    
    # Install ClusterIssuers for Let's Encrypt
    install_cluster_issuers
    
    success "Cert-Manager installed and configured"
}

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
    for i in {1..30}; do
        if kubectl get crd clusterissuers.cert-manager.io &>/dev/null; then
            local crd_established=$(kubectl get crd clusterissuers.cert-manager.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "False")
            if [ "$crd_established" = "True" ]; then
                log "✓ ClusterIssuer CRD is established"
                
                # Test webhook functionality by attempting to list ClusterIssuers (tests API connectivity)
                log "Testing webhook API connectivity..."
                if kubectl get clusterissuer --request-timeout=5s &>/dev/null 2>&1; then
                    log "✓ Webhook API is responding"
                    return 0
                else
                    [ $((i % 5)) -eq 0 ] && log "Webhook API test failed, retrying... ($i/30)"
                fi
            fi
        fi
        [ $((i % 5)) -eq 0 ] && log "Waiting for CRD to be established... ($i/30)"
        sleep 2
    done
    
    warn "CRD may not be fully established or webhook not responding, but continuing..."
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
        local apply_output
        if [ "$VERBOSE" = "true" ]; then
            if kubectl apply -f "$clusterissuer_file"; then
                apply_success=true
                break
            else
                apply_output="kubectl apply failed (see output above)"
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
            if [ "$VERBOSE" = "true" ] || [ -n "$apply_output" ]; then
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

install_cluster_autoscaler() {
    [ "$INSTALL_CLUSTER_AUTOSCALER" != "true" ] && return
    
    # Check if already installed
    if helm list -n kube-system | grep -q cluster-autoscaler; then
        log "Cluster Autoscaler already installed. Verifying configuration..."
        local role_name="${PROJECT_NAME}-cluster-autoscaler-role"
        local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
        if [ -n "$role_arn" ]; then
            local sa_name="cluster-autoscaler-aws-cluster-autoscaler"
            
            # Verify and fix Helm ownership metadata if missing
            local managed_by=$(kubectl get serviceaccount "$sa_name" -n kube-system -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
            if [ "$managed_by" != "Helm" ]; then
                log "Fixing Helm ownership metadata for Cluster Autoscaler ServiceAccount..."
                kubectl label serviceaccount "$sa_name" -n kube-system app.kubernetes.io/managed-by=Helm --overwrite &>/dev/null
                kubectl annotate serviceaccount "$sa_name" -n kube-system \
                    meta.helm.sh/release-name=cluster-autoscaler \
                    meta.helm.sh/release-namespace=kube-system \
                    --overwrite &>/dev/null
            fi
            
            # Verify and fix IRSA annotation
            local current_arn=$(kubectl get serviceaccount "$sa_name" -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
            if [ "$current_arn" != "$role_arn" ]; then
                log "Fixing IRSA annotation for Cluster Autoscaler..."
                kubectl annotate serviceaccount "$sa_name" -n kube-system eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
                log "Restarting Cluster Autoscaler pods..."
                kubectl rollout restart deployment cluster-autoscaler -n kube-system &>/dev/null || \
                kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler &>/dev/null || true
                success "Cluster Autoscaler configuration updated"
            else
                log "Cluster Autoscaler configuration is correct"
            fi
        else
            warn "IAM role not found: $role_name. Skipping configuration fix."
        fi
        return
    fi
    log "Installing Cluster Autoscaler..."
    local role_name="${PROJECT_NAME}-cluster-autoscaler-role"
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
    [ -z "$role_arn" ] && error "IAM role not found: $role_name"
    # The Helm chart creates ServiceAccount with name: <release-name>-<chart-name>
    # Release name is "cluster-autoscaler", chart name is "cluster-autoscaler"
    # So ServiceAccount name is: cluster-autoscaler-aws-cluster-autoscaler
    local sa_name="cluster-autoscaler-aws-cluster-autoscaler"
    
    # Create ServiceAccount if it doesn't exist
    kubectl create serviceaccount "$sa_name" -n kube-system --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Add Helm ownership metadata (REQUIRED for Helm to manage existing ServiceAccount)
    # This prevents "ServiceAccount exists and cannot be imported" error
    kubectl label serviceaccount "$sa_name" -n kube-system app.kubernetes.io/managed-by=Helm --overwrite &>/dev/null
    kubectl annotate serviceaccount "$sa_name" -n kube-system \
        meta.helm.sh/release-name=cluster-autoscaler \
        meta.helm.sh/release-namespace=kube-system \
        --overwrite &>/dev/null
    
    # Add IRSA annotation for AWS IAM role
    kubectl annotate serviceaccount "$sa_name" -n kube-system eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
    helm_repo autoscaler https://kubernetes.github.io/autoscaler
    # Use autoDiscovery mode for EKS - automatically discovers node groups
    # Note: Instance types are controlled by the EKS node group configuration
    # The autoscaler will scale the node groups with their configured instance types
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
            --set "autoDiscovery.clusterName=$CLUSTER_NAME" \
            --set "awsRegion=$AWS_REGION" \
            --set "serviceAccount.create=false" \
            --set "serviceAccount.name=$sa_name" \
            --set "rbac.create=true" \
            --set "extraArgs.scan-interval=10s" \
            --set "extraArgs.skip-nodes-with-local-storage=false" \
            --set "extraArgs.skip-nodes-with-system-pods=false" \
            --wait --timeout 5m
    else
        helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
            --set "autoDiscovery.clusterName=$CLUSTER_NAME" \
            --set "awsRegion=$AWS_REGION" \
            --set "serviceAccount.create=false" \
            --set "serviceAccount.name=$sa_name" \
            --set "rbac.create=true" \
            --set "extraArgs.scan-interval=10s" \
            --set "extraArgs.skip-nodes-with-local-storage=false" \
            --set "extraArgs.skip-nodes-with-system-pods=false" \
            --wait --timeout 5m &>/dev/null
    fi
    success "Cluster Autoscaler installed"
}

install_prometheus() {
    [ "$INSTALL_PROMETHEUS" != "true" ] && return
    helm list -n monitoring | grep -q prometheus && return
    log "Installing Prometheus..."
    helm_repo prometheus-community https://prometheus-community.github.io/helm-charts
    ns monitoring
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --set prometheus.prometheusSpec.retention=30d --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp3 --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi --set prometheus.prometheusSpec.resources.requests.memory=512Mi --set prometheus.prometheusSpec.resources.requests.cpu=250m --set prometheus.prometheusSpec.resources.limits.memory=1Gi --set prometheus.prometheusSpec.resources.limits.cpu=500m --set grafana.enabled=true --wait --timeout 10m
    else
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --set prometheus.prometheusSpec.retention=30d --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp3 --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi --set prometheus.prometheusSpec.resources.requests.memory=512Mi --set prometheus.prometheusSpec.resources.requests.cpu=250m --set prometheus.prometheusSpec.resources.limits.memory=1Gi --set prometheus.prometheusSpec.resources.limits.cpu=500m --set grafana.enabled=true --wait --timeout 10m &>/dev/null
    fi
    success "Prometheus installed"
}

install_efk() {
    [ "$INSTALL_EFK" != "true" ] && return
    helm list -n logging | grep -q elasticsearch && helm list -n logging | grep -q kibana && helm list -n logging | grep -q fluent-bit && return
    log "Installing EFK Stack..."
    helm_repo elastic https://helm.elastic.co
    helm_repo fluent https://fluent.github.io/helm-charts
    ns logging
    if ! helm list -n logging | grep -q elasticsearch; then
        # Create storage class with gp3 if it doesn't exist or has wrong provisioner
        local sc_exists=false
        local sc_provisioner=""
        if kubectl get storageclass gp3 &>/dev/null; then
            sc_exists=true
            sc_provisioner=$(kubectl get storageclass gp3 -o jsonpath='{.provisioner}' 2>/dev/null || echo "")
        fi
        
        if [ "$sc_exists" = false ] || [ "$sc_provisioner" != "ebs.csi.aws.com" ]; then
            if [ "$sc_exists" = true ]; then
                log "StorageClass gp3 exists with wrong provisioner ($sc_provisioner). Deleting and recreating..."
                kubectl delete storageclass gp3 &>/dev/null || warn "Failed to delete storage class, may be in use"
            else
                log "Creating storage class gp3..."
            fi
            if [ -f "$STORAGE_CLASS_FILE" ]; then
                if [ "$VERBOSE" = "true" ]; then
                    kubectl apply -f "$STORAGE_CLASS_FILE" || error "Failed to create storage class from $STORAGE_CLASS_FILE"
                else
                    kubectl apply -f "$STORAGE_CLASS_FILE" &>/dev/null || error "Failed to create storage class from $STORAGE_CLASS_FILE"
                fi
            else
                warn "Storage class file not found at $STORAGE_CLASS_FILE, using inline definition"
                kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  fsType: ext4
EOF
            fi
        else
            log "StorageClass gp3 already exists with correct provisioner"
        fi
        log "Installing Elasticsearch..."
        if [ "$VERBOSE" = "true" ]; then
            helm upgrade --install elasticsearch elastic/elasticsearch -n logging \
              --set replicas=1 \
              --set minimumMasterNodes=1 \
              --set resources.requests.memory=1Gi \
              --set resources.requests.cpu=500m \
              --set resources.limits.memory=2Gi \
              --set resources.limits.cpu=1000m \
              --set persistence.enabled=true \
              --set persistence.storageClass=gp3 \
              --set persistence.size=10Gi \
              --set tls.enabled=true \
              --set tls.selfSigned=true
        else
            log "Installing Elasticsearch (this may take a few minutes)..."
            helm upgrade --install elasticsearch elastic/elasticsearch -n logging \
              --set replicas=1 \
              --set minimumMasterNodes=1 \
              --set resources.requests.memory=1Gi \
              --set resources.requests.cpu=500m \
              --set resources.limits.memory=2Gi \
              --set resources.limits.cpu=1000m \
              --set persistence.enabled=true \
              --set persistence.storageClass=gp3 \
              --set persistence.size=10Gi \
              --set tls.enabled=true \
              --set tls.selfSigned=true &>/dev/null
        fi
        log "Elasticsearch helm installation completed. Polling for pods to be ready (max 5 minutes)..."
        # Wait for Elasticsearch to be ready (5 minutes max), then continue regardless
        wait_for_elasticsearch
    fi
    if ! helm list -n logging | grep -q fluent-bit; then
        log "Installing Fluent-bit (running in background)..."
        helm upgrade --install fluent-bit fluent/fluent-bit -n logging \
          --set backend.type=elasticsearch \
          --set backend.elasticsearch.host=elasticsearch-master.logging.svc.cluster.local \
          --set backend.elasticsearch.port=9200 \
          --set backend.elasticsearch.tls=true \
          --set backend.elasticsearch.tls_verify=false $([ "$VERBOSE" != "true" ] && echo "&>/dev/null") &
        log "Fluent-bit installation started in background..."
    fi
    if ! helm list -n logging | grep -q kibana; then
        log "Installing Kibana (running in background, will wait for Elasticsearch)..."
        # Delete any failed pre-install jobs first
        kubectl delete job -n logging -l job-name=pre-install-kibana-kibana --ignore-not-found=true &>/dev/null
        
        # Create RBAC for Kibana pre-install job to create secrets (as fallback, though hooks are disabled)
        log "Creating RBAC permissions for Kibana pre-install job (hooks disabled, but RBAC added as safety)..."
        kubectl apply -f - <<EOF &>/dev/null || true
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kibana-pre-install
  namespace: logging
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["create", "get", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kibana-pre-install
  namespace: logging
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kibana-pre-install
subjects:
- kind: ServiceAccount
  name: kibana-kibana
  namespace: logging
EOF
        
        # Since hooks are disabled but kibana-values.yml references serviceAccountTokenSecret: kibana-kibana-es-token,
        # the pre-install hook would normally create this secret. Since hooks are disabled, we override it to null.
        # Alternatively, you can enable hooks again since RBAC is now fixed - the hook will create:
        #   Secret name: kibana-kibana-es-token
        #   Namespace: logging
        #   Contains: Elasticsearch service account token for Kibana authentication
        
        local kibana_values_file="$PROJECT_ROOT/k8s/kibana-values.yml"
        if [ -f "$kibana_values_file" ]; then
            if [ "$VERBOSE" = "true" ]; then
                helm upgrade --install kibana elastic/kibana -n logging \
                  -f "$kibana_values_file" \
                  --set resources.requests.memory=512Mi \
                  --set resources.requests.cpu=500m \
                  --set lifecycleHooks.preInstall.enabled=false \
                  --set lifecycleHooks.preUpgrade.enabled=false \
                  --set lifecycleHooks.preRollback.enabled=false \
                  --set lifecycleHooks.preDelete.enabled=false \
                  --set elasticsearch.serviceAccountTokenSecret=null \
                  --wait=false
            else
                helm upgrade --install kibana elastic/kibana -n logging \
                  -f "$kibana_values_file" \
                  --set resources.requests.memory=512Mi \
                  --set resources.requests.cpu=500m \
                  --set lifecycleHooks.preInstall.enabled=false \
                  --set lifecycleHooks.preUpgrade.enabled=false \
                  --set lifecycleHooks.preRollback.enabled=false \
                  --set lifecycleHooks.preDelete.enabled=false \
                  --set elasticsearch.serviceAccountTokenSecret=null \
                  --wait=false &>/dev/null &
            fi
        else
            warn "Kibana values file not found at $kibana_values_file, using inline values"
            helm upgrade --install kibana elastic/kibana -n logging \
              --set elasticsearchHosts=https://elasticsearch-master.logging.svc.cluster.local:9200 \
              --set extraEnvs[0].name=ELASTICSEARCH_HOSTS \
              --set extraEnvs[0].value=https://elasticsearch-master.logging.svc.cluster.local:9200 \
              --set extraEnvs[1].name=ELASTICSEARCH_SSL_VERIFICATIONMODE \
              --set extraEnvs[1].value=none \
              --set resources.requests.memory=512Mi \
              --set resources.requests.cpu=500m \
              --set lifecycleHooks.preInstall.enabled=false \
              --set lifecycleHooks.preUpgrade.enabled=false \
              --set lifecycleHooks.preRollback.enabled=false \
              --set lifecycleHooks.preDelete.enabled=false \
              --wait=false $([ "$VERBOSE" != "true" ] && echo "&>/dev/null") &
        fi
        log "Kibana installation started in background..."
    fi
    success "EFK Stack installed"
}

install_otel_collector() {
    [ "$INSTALL_OTEL_COLLECTOR" != "true" ] && return
    helm list -n observability | grep -q otel-collector && return
    log "Installing OpenTelemetry Collector..."
    helm_repo open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    ns observability
    cat > /tmp/otel-config.yaml <<'EOF'
receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317}
      http: {endpoint: 0.0.0.0:4318}
processors:
  batch: {timeout: 10s, send_batch_size: 1024}
exporters:
  prometheus: {endpoint: "0.0.0.0:8889"}
  logging: {loglevel: info}
service:
  pipelines:
    traces: {receivers: [otlp], processors: [batch], exporters: [logging]}
    metrics: {receivers: [otlp], processors: [batch], exporters: [prometheus, logging]}
    logs: {receivers: [otlp], processors: [batch], exporters: [logging]}
EOF
    kubectl create configmap otel-collector-config --from-file=config=/tmp/otel-config.yaml -n observability --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install otel-collector open-telemetry/opentelemetry-collector -n observability --set mode=deployment --set configMap.name=otel-collector-config --set configMap.create=false --wait --timeout 5m
    else
        helm upgrade --install otel-collector open-telemetry/opentelemetry-collector -n observability --set mode=deployment --set configMap.name=otel-collector-config --set configMap.create=false --wait --timeout 5m &>/dev/null
    fi
    rm -f /tmp/otel-config.yaml
    success "OpenTelemetry Collector installed"
}

main() {
    log "EKS Addons Installation - Cluster: $CLUSTER_NAME | Region: $AWS_REGION"
    [ "$VERBOSE" = "true" ] && log "Verbose mode enabled"
    check_prerequisites
    verify_setup
    wait_for_nodes
    
    # Install core components first
    install_metrics_server
    install_alb_controller
    install_cert_manager
    
    # Install monitoring and logging
    install_prometheus
    install_efk
    install_otel_collector
    
    # Install GitOps and autoscaling
    install_argocd
    install_cluster_autoscaler
    
    # Wait for background processes to complete
    log "Waiting for background installations to complete..."
    wait
    
    # Check installation status
    log "Checking installation status..."
    if [ "$INSTALL_EFK" = "true" ]; then
        log "EFK Stack status:"
        helm list -n logging | grep -E "elasticsearch|kibana|fluent-bit" || warn "Some EFK components not found in helm list"
        kubectl get pods -n logging 2>/dev/null | head -10 || warn "Could not check pods in logging namespace"
    fi
    
    success "Installation completed! Some components may still be starting up."
    log "Check status with: kubectl get pods --all-namespaces"
    log "Check helm releases: helm list --all-namespaces"
}

main "$@"
