# Storage Class using EBS CSI Driver (recommended for EKS 1.34+)
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode     = "WaitForFirstConsumer"
  allow_volume_expansion  = true
  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }
  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# Alternative: Update existing gp2 to use CSI (optional)
# Note: This would require deleting and recreating, which may affect existing PVCs
resource "kubernetes_storage_class_v1" "gp2_csi" {
  metadata {
    name = "gp2-csi"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode     = "WaitForFirstConsumer"
  allow_volume_expansion  = true
  parameters = {
    type      = "gp2"
    fsType    = "ext4"
    encrypted = "true"
  }
  depends_on = [aws_eks_addon.ebs_csi_driver]
}

