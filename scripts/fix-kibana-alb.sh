#!/bin/bash
set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-simple-time-service-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log() { echo "[INFO] $1"; }
success() { echo "[SUCCESS] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="darwin"
            ARCH=$(uname -m)
            if [ "$ARCH" = "arm64" ]; then
                ARCH="arm64"
            else
                ARCH="amd64"
            fi
            ;;
        Linux*)
            OS="linux"
            ARCH="amd64"
            ;;
        *)
            error "Unsupported OS: $(uname -s)"
            ;;
    esac
    log "Detected OS: $OS ($ARCH)"
}

# Install prerequisites
install_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &>/dev/null; then
        if [ "$OS" = "darwin" ]; then
            warn "AWS CLI not found. Install with: brew install awscli"
            error "Please install AWS CLI first"
        else
            error "AWS CLI not found - should be pre-installed on AL2023"
        fi
    fi
    
    # Install kubectl if missing
    if ! command -v kubectl &>/dev/null; then
        log "Installing kubectl..."
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
        chmod +x kubectl
        if [ "$OS" = "darwin" ]; then
            mv kubectl /usr/local/bin/ 2>/dev/null || mv kubectl ~/bin/ 2>/dev/null || error "Could not install kubectl. Please install manually."
        else
            sudo mv kubectl /usr/local/bin/
        fi
        success "kubectl installed"
    fi
    
    # Install helm if missing
    if ! command -v helm &>/dev/null; then
        log "Installing helm..."
        HELM_VERSION="v3.15.0"
        if [ "$OS" = "darwin" ]; then
            curl -LO "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
            tar -zxvf "helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
            mv "${OS}-${ARCH}/helm" /usr/local/bin/ 2>/dev/null || mv "${OS}-${ARCH}/helm" ~/bin/ 2>/dev/null || error "Could not install helm. Please install manually."
            rm -rf "helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz" "${OS}-${ARCH}"
        else
            curl -LO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
            tar -zxvf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
            sudo mv linux-amd64/helm /usr/local/bin/
            rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64
        fi
        success "helm installed"
    fi
    
    success "Prerequisites ready"
}

detect_os

install_prerequisites

# Verify AWS credentials
log "Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured. Ensure EC2 instance has IAM role with EKS access."
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
CURRENT_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
CURRENT_ROLE_NAME=$(echo "$CURRENT_ROLE_ARN" | cut -d'/' -f2)
log "Using AWS account: $AWS_ACCOUNT (Role: $CURRENT_ROLE_ARN)"

# Get EC2 instance IAM role (if running on EC2)
INSTANCE_ROLE_ARN=""
if [ "$OS" = "linux" ] && ([ -f /sys/hypervisor/uuid ] || [ -f /sys/devices/virtual/dmi/id/product_uuid ]); then
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
    if [ -n "$INSTANCE_ID" ]; then
        INSTANCE_PROFILE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "")
        if [ -n "$INSTANCE_PROFILE" ] && [ "$INSTANCE_PROFILE" != "None" ]; then
            INSTANCE_ROLE_NAME=$(echo "$INSTANCE_PROFILE" | cut -d'/' -f2)
            INSTANCE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT}:role/${INSTANCE_ROLE_NAME}"
            log "Detected EC2 instance role: $INSTANCE_ROLE_ARN"
        fi
    fi
fi

# Verify EKS cluster access
log "Verifying EKS cluster access..."
if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
    error "Cannot access EKS cluster. Ensure IAM role has 'eks:DescribeCluster' permission."
fi

# Try to get EKS node role ARN (which should already have access)
EKS_NODE_ROLE_ARN=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text 2>/dev/null)
# Actually, let's get the node group role
NODE_GROUP_ROLE=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "${CLUSTER_NAME}-node-group" --region "$AWS_REGION" \
    --query 'nodegroup.nodeRole' --output text 2>/dev/null || echo "")

# Update kubeconfig - try using node role if available, otherwise use current role
if [ -n "$NODE_GROUP_ROLE" ] && [ "$NODE_GROUP_ROLE" != "None" ]; then
    log "Attempting to use EKS node role for kubectl access..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" --role-arn "$NODE_GROUP_ROLE" 2>/dev/null || \
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || error "Failed to update kubeconfig"
else
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || error "Failed to update kubeconfig"
fi

# Verify kubectl can connect (retry a few times as token generation may take a moment)
log "Verifying kubectl connection..."
KUBECTL_WORKS=false
for i in {1..5}; do
    if kubectl cluster-info &>/dev/null 2>&1; then
        success "Connected to cluster: $CLUSTER_NAME"
        KUBECTL_WORKS=true
        break
    fi
    log "Retrying connection... ($i/5)"
    sleep 2
done

# If kubectl still doesn't work, try to add current AWS identity to aws-auth using eksctl
if [ "$KUBECTL_WORKS" = false ]; then
    warn "Cannot connect to cluster. Attempting to add current AWS identity to aws-auth..."
    
    # Determine which ARN to use: instance role (if on EC2) or current identity (if on Mac/local)
    ROLE_TO_ADD=""
    if [ -n "$INSTANCE_ROLE_ARN" ]; then
        ROLE_TO_ADD="$INSTANCE_ROLE_ARN"
        log "Using EC2 instance role: $ROLE_TO_ADD"
    else
        # Use current AWS identity (IAM user or role)
        ROLE_TO_ADD="$CURRENT_ROLE_ARN"
        log "Using current AWS identity: $ROLE_TO_ADD"
    fi
    
    if [ -n "$ROLE_TO_ADD" ]; then
        # Try to install eksctl and use it to add the role
        if ! command -v eksctl &>/dev/null; then
            log "Installing eksctl to update aws-auth..."
            if [ "$OS" = "darwin" ]; then
                if [ "$ARCH" = "arm64" ]; then
                    EKSCTL_ARCH="arm64"
                else
                    EKSCTL_ARCH="amd64"
                fi
                curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Darwin_${EKSCTL_ARCH}.tar.gz" 2>/dev/null || true
                if [ -f "eksctl_Darwin_${EKSCTL_ARCH}.tar.gz" ]; then
                    tar -xzf "eksctl_Darwin_${EKSCTL_ARCH}.tar.gz" 2>/dev/null || true
                    mv eksctl /usr/local/bin/ 2>/dev/null || mv eksctl ~/bin/ 2>/dev/null || true
                    rm -f "eksctl_Darwin_${EKSCTL_ARCH}.tar.gz" 2>/dev/null || true
                fi
            else
                curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" 2>/dev/null || true
                if [ -f "eksctl_$(uname -s)_amd64.tar.gz" ]; then
                    tar -xzf "eksctl_$(uname -s)_amd64.tar.gz" 2>/dev/null || true
                    sudo mv eksctl /usr/local/bin/ 2>/dev/null || true
                    rm -f "eksctl_$(uname -s)_amd64.tar.gz" 2>/dev/null || true
                fi
            fi
        fi
        
        if command -v eksctl &>/dev/null; then
            log "Adding AWS identity to aws-auth using eksctl..."
            if eksctl create iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
                --arn "$ROLE_TO_ADD" --group system:masters --username admin 2>/dev/null; then
                success "Added AWS identity to aws-auth"
                log "Retrying kubectl connection..."
                sleep 3
                if kubectl cluster-info &>/dev/null 2>&1; then
                    success "Connected to cluster: $CLUSTER_NAME"
                    KUBECTL_WORKS=true
                fi
            else
                warn "eksctl failed to add identity. It may already exist or you may need different permissions."
            fi
        fi
    fi
    
    # If still not working, provide manual instructions
    if [ "$KUBECTL_WORKS" = false ]; then
        warn "Cannot connect to cluster. Manual steps required:"
        echo ""
        if [ -n "$ROLE_TO_ADD" ]; then
            echo "Add this AWS identity to EKS aws-auth ConfigMap:"
            echo "  Identity ARN: $ROLE_TO_ADD"
            echo ""
            echo "Option 1: Using eksctl (recommended):"
            echo "  eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region $AWS_REGION \\"
            echo "    --arn \"$ROLE_TO_ADD\" --group system:masters --username admin"
            echo ""
            echo "Option 2: Using kubectl from a machine that already has access:"
            echo "  kubectl edit configmap aws-auth -n kube-system"
            echo "  Then add to mapRoles (if IAM role) or mapUsers (if IAM user):"
            if echo "$ROLE_TO_ADD" | grep -q ":user/"; then
                echo "  mapUsers:"
                echo "  - userarn: $ROLE_TO_ADD"
                echo "    username: admin"
                echo "    groups:"
                echo "    - system:masters"
            else
                echo "  mapRoles:"
                echo "  - rolearn: $ROLE_TO_ADD"
                echo "    username: admin"
                echo "    groups:"
                echo "    - system:masters"
            fi
        else
            echo "Could not determine AWS identity. Current identity: $CURRENT_ROLE_ARN"
            echo ""
            echo "Add your AWS identity to aws-auth ConfigMap using eksctl or kubectl."
        fi
        error "kubectl authentication failed. Please add the AWS identity to aws-auth ConfigMap first."
    fi
fi

# Fix Kibana
log "Fixing Kibana configuration..."
kubectl delete deployment kibana-kibana -n logging --ignore-not-found=true
kubectl delete job -l app=kibana-kibana -n logging --ignore-not-found=true
kubectl delete pod -l app=kibana-kibana -n logging --ignore-not-found=true

log "Waiting for resources to be deleted..."
sleep 10

log "Adding Elastic Helm repo..."
helm repo add elastic https://helm.elastic.co &>/dev/null || true
helm repo update elastic &>/dev/null

log "Reinstalling Kibana with HTTPS configuration..."
helm upgrade --install kibana elastic/kibana -n logging \
  --set elasticsearchHosts=https://elasticsearch-master.logging.svc.cluster.local:9200 \
  --set extraEnvs[0].name=ELASTICSEARCH_HOSTS \
  --set extraEnvs[0].value=https://elasticsearch-master.logging.svc.cluster.local:9200 \
  --set extraEnvs[1].name=ELASTICSEARCH_SSL_VERIFICATIONMODE \
  --set extraEnvs[1].value=none \
  --set resources.requests.memory=512Mi \
  --set resources.requests.cpu=500m \
  --wait --timeout=10m

success "Kibana reinstalled with HTTPS"

# Fix AWS Load Balancer Controller (if needed)
log "Checking AWS Load Balancer Controller..."
if kubectl get deployment aws-load-balancer-controller -n kube-system &>/dev/null; then
    log "Checking controller pod status..."
    if kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --field-selector=status.phase!=Running &>/dev/null; then
        warn "AWS Load Balancer Controller has issues, checking logs..."
        local pod=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$pod" ]; then
            log "Controller pod: $pod"
            kubectl logs "$pod" -n kube-system --tail=20 || true
        fi
        
        # Get VPC ID and update if needed
        local vpc_id=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)
        if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
            log "Adding EKS Helm repo..."
            helm repo add eks https://aws.github.io/eks-charts &>/dev/null || true
            helm repo update eks &>/dev/null
            log "Updating AWS Load Balancer Controller with VPC ID: $vpc_id"
            helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
              -n kube-system \
              --reuse-values \
              --set vpcId="$vpc_id" \
              --wait --timeout=5m
            success "AWS Load Balancer Controller updated"
        else
            warn "Could not get VPC ID, controller should auto-detect"
        fi
    else
        success "AWS Load Balancer Controller is running"
    fi
else
    warn "AWS Load Balancer Controller not found"
fi

# Wait and verify
log "Waiting for Kibana to be ready..."
kubectl wait --for=condition=Ready pod -l app=kibana-kibana -n logging --timeout=5m &>/dev/null || warn "Kibana may still be starting"

log "Checking pod status..."
echo ""
echo "=== Kibana Pods ==="
kubectl get pods -n logging -l app=kibana-kibana
echo ""
echo "=== AWS Load Balancer Controller Pods ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller || echo "Not found"

success "Fix script completed!"
log "Check logs with: kubectl logs -n logging -l app=kibana-kibana"

