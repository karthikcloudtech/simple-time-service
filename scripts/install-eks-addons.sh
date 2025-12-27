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
        curl -s -o /tmp/alb-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json
        aws iam create-policy --policy-name "$policy_name" --policy-document file:///tmp/alb-policy.json &>/dev/null
        rm -f /tmp/alb-policy.json
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

install_cert_manager() {
    [ "$INSTALL_CERT_MANAGER" != "true" ] && return
    helm list -n cert-manager | grep -q cert-manager && return
    log "Installing Cert-Manager..."
    helm_repo jetstack https://charts.jetstack.io
    ns cert-manager
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml &>/dev/null
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --set installCRDs=false --wait --timeout 5m
    else
        helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --set installCRDs=false --wait --timeout 5m &>/dev/null
    fi
    kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=5m &>/dev/null
    kubectl wait --for=condition=available deployment/cert-manager-cainjector -n cert-manager --timeout=5m &>/dev/null
    success "Cert-Manager installed"
}

install_cluster_autoscaler() {
    [ "$INSTALL_CLUSTER_AUTOSCALER" != "true" ] && return
    helm list -n kube-system | grep -q cluster-autoscaler && return
    log "Installing Cluster Autoscaler..."
    local role_name="${PROJECT_NAME}-cluster-autoscaler-role"
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
    [ -z "$role_arn" ] && error "IAM role not found: $role_name"
    kubectl create serviceaccount cluster-autoscaler -n kube-system --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    kubectl annotate serviceaccount cluster-autoscaler -n kube-system eks.amazonaws.com/role-arn="$role_arn" --overwrite &>/dev/null
    helm_repo autoscaler https://kubernetes.github.io/autoscaler
    # Use autoDiscovery mode for EKS - automatically discovers node groups
    # Note: Instance types are controlled by the EKS node group configuration
    # The autoscaler will scale the node groups with their configured instance types
    if [ "$VERBOSE" = "true" ]; then
        helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
            --set "autoDiscovery.clusterName=$CLUSTER_NAME" \
            --set "awsRegion=$AWS_REGION" \
            --set "serviceAccount.create=false" \
            --set "serviceAccount.name=cluster-autoscaler" \
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
            --set "serviceAccount.name=cluster-autoscaler" \
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
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --set prometheus.prometheusSpec.retention=30d --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi --set prometheus.prometheusSpec.resources.requests.memory=512Mi --set prometheus.prometheusSpec.resources.requests.cpu=250m --set prometheus.prometheusSpec.resources.limits.memory=1Gi --set prometheus.prometheusSpec.resources.limits.cpu=500m --set grafana.enabled=true --wait --timeout 10m
    else
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --set prometheus.prometheusSpec.retention=30d --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi --set prometheus.prometheusSpec.resources.requests.memory=512Mi --set prometheus.prometheusSpec.resources.requests.cpu=250m --set prometheus.prometheusSpec.resources.limits.memory=1Gi --set prometheus.prometheusSpec.resources.limits.cpu=500m --set grafana.enabled=true --wait --timeout 10m &>/dev/null
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
        log "Installing Elasticsearch (running in background)..."
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
          --set tls.selfSigned=true $([ "$VERBOSE" != "true" ] && echo "&>/dev/null") &
        log "Elasticsearch installation started in background, continuing with other components..."
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
          --set lifecycleHooks.preRollback.enabled=false $([ "$VERBOSE" != "true" ] && echo "&>/dev/null") &
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
    
    success "Installation completed! Some components may still be starting up."
    log "Check status with: kubectl get pods --all-namespaces"
}

main "$@"
