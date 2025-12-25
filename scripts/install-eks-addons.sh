#!/bin/bash

###############################################################################
# EKS Cluster Addons Installation Script
# Installs AWS Load Balancer Controller, ArgoCD, and other required components
###############################################################################

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-simple-time-service}"

# Installation options
INSTALL_ALB_CONTROLLER="${INSTALL_ALB_CONTROLLER:-true}"
INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"
INSTALL_METRICS_SERVER="${INSTALL_METRICS_SERVER:-true}"
INSTALL_CLUSTER_AUTOSCALER="${INSTALL_CLUSTER_AUTOSCALER:-false}"
INSTALL_CERT_MANAGER="${INSTALL_CERT_MANAGER:-true}"
INSTALL_PROMETHEUS="${INSTALL_PROMETHEUS:-true}"
INSTALL_EFK="${INSTALL_EFK:-true}"
INSTALL_OTEL_COLLECTOR="${INSTALL_OTEL_COLLECTOR:-true}"

###############################################################################
# Helper Functions
###############################################################################

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_prerequisites() {
    log "Checking prerequisites..."
    local missing=false
    
    for cmd in kubectl helm aws jq; do
        if ! command -v "$cmd" &> /dev/null; then
            warn "$cmd is not installed"
            missing=true
        fi
    done
    
    if [ "$missing" = true ]; then
        error "Missing prerequisites. Please install them and try again."
    fi
    success "All prerequisites installed"
}

verify_setup() {
    log "Verifying AWS authentication..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure'"
    fi
    local account=$(aws sts get-caller-identity --query Account --output text)
    success "AWS authenticated (Account: $account)"
    
    log "Verifying kubectl connection..."
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        log "Updating kubeconfig..."
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || \
            error "Failed to update kubeconfig"
    fi
    success "Connected to cluster: $CLUSTER_NAME"
}

wait_for_nodes() {
    log "Waiting for at least one node to be ready..."
    local max_attempts=60
    local attempt=0
    local ready_nodes=0
    
    while [ $attempt -lt $max_attempts ]; do
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        
        if [ "$ready_nodes" -gt 0 ]; then
            success "Found $ready_nodes ready node(s)"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 5)) -eq 0 ]; then
            log "Still waiting for nodes to be ready... (attempt $attempt/$max_attempts)"
        fi
        sleep 10
    done
    
    error "Timeout waiting for nodes to be ready. Please ensure the cluster has active node groups."
}

###############################################################################
# AWS Load Balancer Controller
###############################################################################

install_alb_controller() {
    [ "$INSTALL_ALB_CONTROLLER" != "true" ] && { log "Skipping ALB Controller"; return; }
    
    log "Installing AWS Load Balancer Controller..."
    
    # Get OIDC issuer
    local oidc_issuer=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
        --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
    
    [ -z "$oidc_issuer" ] || [ "$oidc_issuer" == "None" ] && \
        error "OIDC issuer not found. Enable OIDC provider on EKS cluster."
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_name="${PROJECT_NAME}-aws-load-balancer-controller-policy"
    local role_name="${PROJECT_NAME}-aws-load-balancer-controller-role"
    local sa_name="aws-load-balancer-controller"
    local sa_namespace="kube-system"
    
    # Create OIDC provider if needed
    if ! aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$oidc_issuer')].Arn" --output text | grep -q .; then
        log "Creating OIDC provider..."
        local thumbprint=$(openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com \
            -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>/dev/null | \
            openssl x509 -fingerprint -noout -sha1 | cut -d'=' -f2 | tr -d ':')
        
        aws iam create-open-id-connect-provider \
            --url "https://${oidc_issuer}" \
            --client-id-list "sts.amazonaws.com" \
            --thumbprint-list "$thumbprint" 2>/dev/null || \
            warn "OIDC provider may already exist"
    fi
    
    # Create IAM policy
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${account_id}:policy/${policy_name}" &>/dev/null; then
        log "Creating IAM policy..."
        curl -s -o /tmp/alb-policy.json \
            https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json
        aws iam create-policy --policy-name "$policy_name" \
            --policy-document file:///tmp/alb-policy.json &>/dev/null
        rm -f /tmp/alb-policy.json
        success "IAM policy created"
    fi
    
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
    
    # Create IAM role
    cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_issuer}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${oidc_issuer}:sub": "system:serviceaccount:${sa_namespace}:${sa_name}",
        "${oidc_issuer}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF
    
    if ! aws iam get-role --role-name "$role_name" &>/dev/null; then
        aws iam create-role --role-name "$role_name" \
            --assume-role-policy-document file:///tmp/trust-policy.json &>/dev/null
        success "IAM role created"
    else
        aws iam update-assume-role-policy --role-name "$role_name" \
            --policy-document file:///tmp/trust-policy.json &>/dev/null
    fi
    
    aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" &>/dev/null || true
    rm -f /tmp/trust-policy.json
    
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
    
    # Install via Helm
    helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
    helm repo update eks &>/dev/null
    
    kubectl create namespace "$sa_namespace" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    kubectl create serviceaccount "$sa_name" -n "$sa_namespace" \
        --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    kubectl annotate serviceaccount "$sa_name" -n "$sa_namespace" \
        eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
    
    log "Installing ALB Controller via Helm..."
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n "$sa_namespace" \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name="$sa_name" \
        --set region="$AWS_REGION" \
        --wait --timeout 5m &>/dev/null
    
    success "AWS Load Balancer Controller installed"
}

###############################################################################
# Metrics Server
###############################################################################

install_metrics_server() {
    [ "$INSTALL_METRICS_SERVER" != "true" ] && { log "Skipping Metrics Server"; return; }
    
    log "Installing Metrics Server..."
    
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        log "Metrics Server already installed"
        return
    fi
    
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
    helm repo update metrics-server &>/dev/null
    
    helm upgrade --install metrics-server metrics-server/metrics-server \
        -n kube-system \
        --set args="{--kubelet-insecure-tls}" \
        --wait --timeout 3m &>/dev/null
    
    success "Metrics Server installed"
}

###############################################################################
# ArgoCD
###############################################################################

install_argocd() {
    [ "$INSTALL_ARGOCD" != "true" ] && { log "Skipping ArgoCD"; return; }
    
    log "Installing ArgoCD..."
    
    if kubectl get deployment argocd-server -n argocd &>/dev/null; then
        log "ArgoCD already installed"
        return
    fi
    
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    log "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=5m &>/dev/null
    
    success "ArgoCD installed"
    
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [ -n "$password" ]; then
        log "ArgoCD credentials:"
        echo -e "  Username: ${GREEN}admin${NC}"
        echo -e "  Password: ${GREEN}$password${NC}"
        warn "Change password after first login"
        log "Access UI: ${BLUE}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
    fi
}

###############################################################################
# Cert-Manager
###############################################################################

install_cert_manager() {
    [ "$INSTALL_CERT_MANAGER" != "true" ] && { log "Skipping Cert-Manager"; return; }
    
    log "Installing Cert-Manager..."
    
    if kubectl get deployment cert-manager -n cert-manager &>/dev/null; then
        log "Cert-Manager already installed"
        return
    fi
    
    # Add cert-manager Helm repository
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update jetstack &>/dev/null
    
    # Create cert-manager namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Install cert-manager CRDs first
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml &>/dev/null
    
    # Install cert-manager via Helm
    log "Installing Cert-Manager via Helm..."
    helm upgrade --install cert-manager jetstack/cert-manager \
        -n cert-manager \
        --set installCRDs=false \
        --wait --timeout 5m &>/dev/null
    
    success "Cert-Manager installed"
    
    # Wait for cert-manager to be ready
    log "Waiting for Cert-Manager to be ready..."
    kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-cainjector -n cert-manager --timeout=5m &>/dev/null
    
    success "Cert-Manager is ready"
    
    # Apply ClusterIssuer resources for Let's Encrypt
    log "Applying Let's Encrypt ClusterIssuers..."
    # Try multiple possible paths relative to script location
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(cd "$script_dir/.." && pwd)"
    local clusterissuer_path="$project_root/gitops/apps/simple-time-service/base/clusterissuer.yaml"
    
    if [ -f "$clusterissuer_path" ]; then
        kubectl apply -f "$clusterissuer_path" &>/dev/null && \
            success "ClusterIssuers applied" || \
            warn "Failed to apply ClusterIssuers, but continuing..."
    else
        warn "ClusterIssuer file not found at $clusterissuer_path"
        warn "ClusterIssuers can be applied manually later with:"
        warn "  kubectl apply -f gitops/apps/simple-time-service/base/clusterissuer.yaml"
    fi
}

###############################################################################
# Cluster Autoscaler
###############################################################################

install_cluster_autoscaler() {
    [ "$INSTALL_CLUSTER_AUTOSCALER" != "true" ] && { log "Skipping Cluster Autoscaler"; return; }
    
    log "Installing Cluster Autoscaler..."
    warn "IAM role must exist: ${PROJECT_NAME}-cluster-autoscaler-role"
    
    local role_name="${PROJECT_NAME}-cluster-autoscaler-role"
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
    
    [ -z "$role_arn" ] && { error "IAM role not found: $role_name. Create it with Terraform first."; }
    
    local sa_name="cluster-autoscaler"
    local sa_namespace="kube-system"
    
    kubectl create serviceaccount "$sa_name" -n "$sa_namespace" \
        --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    kubectl annotate serviceaccount "$sa_name" -n "$sa_namespace" \
        eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
    
    helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
    helm repo update autoscaler &>/dev/null
    
    helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
        -n "$sa_namespace" \
        --set "autoDiscovery.clusterName=$CLUSTER_NAME" \
        --set "awsRegion=$AWS_REGION" \
        --set "serviceAccount.create=false" \
        --set "serviceAccount.name=$sa_name" \
        --set "rbac.create=true" \
        --wait --timeout 5m &>/dev/null
    
    success "Cluster Autoscaler installed"
}

###############################################################################
# Prometheus
###############################################################################

install_prometheus() {
    [ "$INSTALL_PROMETHEUS" != "true" ] && { log "Skipping Prometheus"; return; }
    log "Installing Prometheus..."
    
    kubectl get deployment prometheus-server -n monitoring &>/dev/null && { log "Prometheus already installed"; return; }
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update prometheus-community &>/dev/null
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        -n monitoring \
        --set prometheus.prometheusSpec.retention=30d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi \
        --set grafana.enabled=true \
        --wait --timeout 10m &>/dev/null
    
    success "Prometheus installed"
    log "Access Grafana: ${BLUE}kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80${NC}"
    log "Default Grafana password: ${BLUE}admin${NC} (check secret: prometheus-grafana)"
}

###############################################################################
# EFK Stack (Elasticsearch, Fluent Bit, Kibana)
###############################################################################

install_efk() {
    [ "$INSTALL_EFK" != "true" ] && { log "Skipping EFK Stack"; return; }
    log "Installing EFK Stack (Elasticsearch, Fluent Bit, Kibana)..."
    
    kubectl get deployment elasticsearch -n logging &>/dev/null && { log "EFK Stack already installed"; return; }
    
    helm repo add elastic https://helm.elastic.co 2>/dev/null || true
    helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true
    helm repo update elastic fluent &>/dev/null
    
    kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Install Elasticsearch
    log "Installing Elasticsearch..."
    helm upgrade --install elasticsearch elastic/elasticsearch \
        -n logging \
        --set replicas=1 \
        --set minimumMasterNodes=1 \
        --set resources.requests.memory=2Gi \
        --set resources.requests.cpu=1000m \
        --set resources.limits.memory=4Gi \
        --set resources.limits.cpu=2000m \
        --wait --timeout 10m &>/dev/null || warn "Elasticsearch installation may need more time"
    
    # Install Fluent Bit
    log "Installing Fluent Bit..."
    helm upgrade --install fluent-bit fluent/fluent-bit \
        -n logging \
        --set backend.type=elasticsearch \
        --set backend.elasticsearch.host=elasticsearch-master.logging.svc.cluster.local \
        --set backend.elasticsearch.port=9200 \
        --wait --timeout 5m &>/dev/null
    
    # Install Kibana
    log "Installing Kibana..."
    helm upgrade --install kibana elastic/kibana \
        -n logging \
        --set elasticsearchHosts=http://elasticsearch-master:9200 \
        --set resources.requests.memory=512Mi \
        --set resources.requests.cpu=500m \
        --wait --timeout 10m &>/dev/null || warn "Kibana installation may need more time"
    
    success "EFK Stack installed"
    log "Access Kibana: ${BLUE}kubectl port-forward svc/kibana-kibana -n logging 5601:5601${NC}"
}

###############################################################################
# OpenTelemetry Collector
###############################################################################

install_otel_collector() {
    [ "$INSTALL_OTEL_COLLECTOR" != "true" ] && { log "Skipping OpenTelemetry Collector"; return; }
    log "Installing OpenTelemetry Collector..."
    
    kubectl get deployment otel-collector -n observability &>/dev/null && { log "OpenTelemetry Collector already installed"; return; }
    
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
    helm repo update open-telemetry &>/dev/null
    
    kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    # Create OpenTelemetry Collector config
    cat > /tmp/otel-config.yaml <<'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
  logging:
    loglevel: info

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
EOF
    
    # Create ConfigMap
    kubectl create configmap otel-collector-config \
        --from-file=config=/tmp/otel-config.yaml \
        -n observability \
        --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    
    helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
        -n observability \
        --set mode=deployment \
        --set configMap.name=otel-collector-config \
        --set configMap.create=false \
        --wait --timeout 5m &>/dev/null
    
    rm -f /tmp/otel-config.yaml
    
    success "OpenTelemetry Collector installed"
}

###############################################################################
# Main
###############################################################################

main() {
    echo -e "${BLUE}==========================================${NC}"
    log "EKS Addons Installation Script"
    echo -e "${BLUE}==========================================${NC}"
    log "Cluster: $CLUSTER_NAME | Region: $AWS_REGION | Project: $PROJECT_NAME"
    echo ""
    
    check_prerequisites
    verify_setup
    wait_for_nodes
    echo ""
    
    log "Starting installations..."
    install_metrics_server
    install_alb_controller
    install_cert_manager
    install_prometheus
    install_efk
    install_otel_collector
    install_argocd
    install_cluster_autoscaler
    
    echo ""
    success "Installation completed!"
    log "Verify: ${BLUE}kubectl get pods -A${NC}"
}

main "$@"
