resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn = aws_iam_role.eks_node_role.arn
  subnet_ids     = var.subnet_ids
  instance_types = ["m7i-flex.large"]
  capacity_type  = "SPOT"
  ami_type       = "AL2023_x86_64_STANDARD"  # EKS-optimized Amazon Linux 2023 AMI for x86_64
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }
  update_config {
    max_unavailable = 1
  }
  
  # Tags required for Cluster Autoscaler to identify and manage this node group
  # These tags are automatically propagated to the underlying Auto Scaling Group
  # Required tags:
  #   - k8s.io/cluster-autoscaler/enabled: "true" (enables autoscaling)
  #   - k8s.io/cluster-autoscaler/<cluster-name>: "owned" (identifies ownership)
  tags = merge(
    { Name = "${var.cluster_name}-node-group" },
    {
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled" = "true"
    }
  )
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_node_policies
  ]
  timeouts {
    create = "20m"
    update = "20m"
    delete = "15m"
  }

  lifecycle {
    create_before_destroy = true
  }
}