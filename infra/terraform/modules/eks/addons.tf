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
    aws_iam_role.external_dns
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "=========================================="
      echo "Installing EKS Addons via Terraform"
      echo "Cluster: ${aws_eks_cluster.main.name}"
      echo "Region: ${var.aws_region}"
      echo "=========================================="
      
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
      
      # Get script path (from terraform module to project root)
      # Module is at: infra/terraform/modules/eks
      # Script is at: scripts/install-eks-addons.sh
      # Go up 4 levels from module to project root
      SCRIPT_PATH="${path.root}/../../../../scripts/install-eks-addons.sh"
      
      # Alternative: Use relative path from project root
      # SCRIPT_PATH="${path.cwd}/scripts/install-eks-addons.sh"
      
      if [ -f "$SCRIPT_PATH" ]; then
        echo "Running installation script: $SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        CLUSTER_NAME="${aws_eks_cluster.main.name}" \
        AWS_REGION="${var.aws_region}" \
        PROJECT_NAME="${var.project_name}" \
        INSTALL_ALB_CONTROLLER="true" \
        INSTALL_ARGOCD="true" \
        INSTALL_METRICS_SERVER="true" \
        INSTALL_CERT_MANAGER="true" \
        INSTALL_PROMETHEUS="true" \
        INSTALL_EFK="true" \
        INSTALL_OTEL_COLLECTOR="true" \
        INSTALL_CLUSTER_AUTOSCALER="true" \
        bash "$SCRIPT_PATH"
      else
        echo "Warning: Installation script not found at: $SCRIPT_PATH"
        echo "Please install addons manually or update the script path"
        echo "Run: ./scripts/install-eks-addons.sh"
        exit 1
      fi
    EOT

    environment = {
      KUBECONFIG = "${path.module}/.kubeconfig"
      AWS_DEFAULT_REGION = var.aws_region
    }
  }

  # Cleanup on destroy (optional)
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Note: Addons will remain in cluster - cleanup manually if needed'"
  }
}

