# Kubernetes Module - Service Accounts and RBAC
# Creates service accounts for JupyterHub users with S3 access

# =============================================================================
# AWS Auth ConfigMap - Grants IAM roles/users access to the EKS cluster
# =============================================================================
# The aws-auth ConfigMap maps IAM identities to Kubernetes RBAC permissions.
# Node roles are added automatically by EKS; we add admin roles/users here.

locals {
  # Build mapRoles YAML - node role + additional admin roles
  map_roles = yamlencode(concat(
    # Node role (required for nodes to join cluster)
    [{
      rolearn  = var.node_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }],
    # Additional admin roles (e.g., GitHub Actions role)
    [for role in var.cluster_admin_roles : {
      rolearn  = role.arn
      username = role.username
      groups   = ["system:masters"]
    }]
  ))

  # Build mapUsers YAML - admin users
  map_users = length(var.cluster_admin_users) > 0 ? yamlencode([
    for user in var.cluster_admin_users : {
      userarn  = user.arn
      username = user.username
      groups   = ["system:masters"]
    }
  ]) : ""
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = merge(
    { mapRoles = local.map_roles },
    length(var.cluster_admin_users) > 0 ? { mapUsers = local.map_users } : {}
  )

  force = true # Overwrite existing data
}

# GP3 Storage Class (default)
# Benefits: 20% cheaper than gp2, 3000 IOPS baseline regardless of size
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
    # Tag dynamically-provisioned EBS volumes with the cluster name so teardown
    # verification (verify-clean-teardown.sh) can attribute any orphaned volume
    # to this environment. The EBS CSI driver applies these at create time.
    "tagSpecification_1" = "Application=jupyterhub"
    "tagSpecification_2" = "KubernetesCluster=${var.cluster_name}"
  }
}

# Remove default annotation from gp2 (EKS creates this automatically)
resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  # Ignore if gp2 doesn't exist (won't fail on fresh cluster)
  force = false

  depends_on = [kubernetes_storage_class_v1.gp3]
}

# Create daskhub namespace
resource "kubernetes_namespace" "daskhub" {
  metadata {
    name = "daskhub"
    labels = {
      name = "daskhub"
    }
  }
}

# Create the Kubernetes service account for user pods
# Pod Identity handles IAM - no IRSA annotations needed
resource "kubernetes_service_account" "user_sa" {
  metadata {
    name      = "user-sa"
    namespace = kubernetes_namespace.daskhub.metadata[0].name
    # No annotations needed - Pod Identity association is in main.tf
  }

  depends_on = [kubernetes_namespace.daskhub]
}
