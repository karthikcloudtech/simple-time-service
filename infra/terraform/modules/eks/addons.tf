# Install EKS Addons after cluster is created
# This runs the installation script as part of Terraform
# 
# Note: This requires kubectl and helm to be installed where Terraform runs
# Set SKIP_ADDONS_INSTALL=true to skip this step and install manually

variable "aws_region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "us-east-1"
}

variable "skip_addons_install" {
  description = "Skip automatic addons installation (install manually instead)"
  type        = bool
  default     = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "null_resource" "install_eks_addons" {
  count = var.skip_addons_install ? 0 : 1

  # Trigger when cluster or node group changes
  triggers = {
    cluster_name    = aws_eks_cluster.main.name
    node_group_id   = aws_eks_node_group.main.id
    cluster_version = aws_eks_cluster.main.version
    region          = var.aws_region
  }

  # Wait for cluster and nodes to be ready
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main,
    aws_iam_openid_connect_provider.eks,
    aws_iam_role.cluster_autoscaler,
    aws_iam_role.aws_load_balancer_controller,
    aws_iam_role.ebs_csi_driver,
    aws_iam_role.efs_csi_driver,
    aws_iam_role.external_dns,
    aws_iam_role.cert_manager
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      
      # Ensure PATH includes common locations
      export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
      
      echo "=========================================="
      echo "Installing EKS Addons via Terraform"
      echo "Cluster: ${aws_eks_cluster.main.name}"
      echo "Region: ${var.aws_region}"
      echo "=========================================="
      
      # Verify tools are available
      command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI not found"; exit 1; }
      command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }
      command -v helm >/dev/null 2>&1 || { echo "Error: helm not found"; exit 1; }
      
      # Update kubeconfig
      echo "Updating kubeconfig..."
      aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} || {
        echo "Error: Failed to update kubeconfig"
        exit 1
      }
      
      # Wait for nodes to be ready (with timeout)
      echo "Waiting for nodes to be ready..."
      timeout 600 bash -c 'until kubectl get nodes 2>/dev/null | grep -q Ready; do echo "Waiting for nodes..."; sleep 10; done' || {
        echo "Warning: Nodes may not be ready yet, continuing anyway..."
      }
      
      # Get script path (from terraform root module to project root)
      # Root module is at: infra/environments/prod
      # Script is at: scripts/install-eks-addons.sh
      # Go up 3 levels from root module to project root: prod -> environments -> infra -> project root
      SCRIPT_PATH="${path.root}/../../../scripts/install-eks-addons.sh"
      
      # Try alternative path if first doesn't exist (from current working directory)
      if [ ! -f "$SCRIPT_PATH" ]; then
        SCRIPT_PATH="${path.cwd}/../../../scripts/install-eks-addons.sh"
      fi
      
      if [ -f "$SCRIPT_PATH" ]; then
        echo "Running installation script: $SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        CLUSTER_NAME="${aws_eks_cluster.main.name}" \
        AWS_REGION="${var.aws_region}" \
        TERRAFORM_DIR="$(pwd)" \
        bash "$SCRIPT_PATH"
      else
        echo "Error: Installation script not found at: $SCRIPT_PATH"
        echo "Tried paths:"
        echo "  - ${path.root}/../../scripts/install-eks-addons.sh"
        echo "  - ${path.cwd}/../../scripts/install-eks-addons.sh"
        echo "Current directory: $(pwd)"
        echo "Please install addons manually or update the script path"
        exit 1
      fi
    EOT

    environment = {
      KUBECONFIG = "${path.module}/.kubeconfig"
      AWS_DEFAULT_REGION = var.aws_region
      # AWS credentials should be available from GitLab CI/CD variables
      # They are passed through from the shell environment to local-exec
    }
  }

  # Cleanup on destroy (optional)
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Note: Addons will remain in cluster - cleanup manually if needed'"
  }
}

