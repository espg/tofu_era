# Kubernetes Module - Service Accounts and RBAC
# Creates service accounts for JupyterHub users with S3 access

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

# Create user service account with S3 access via IRSA
module "user_s3_irsa" {
  source = "../irsa"

  cluster_name      = var.cluster_name
  oidc_provider_arn = var.oidc_provider_arn
  namespace         = "daskhub"
  service_account   = "user-sa"

  policy_statements = [
    # Allow listing all accessible buckets
    {
      Effect = "Allow"
      Action = [
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ]
      Resource = "*"
    },
    # Full access to ALL buckets in this account
    # This gives broad S3 access - restrict if needed for production
    {
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:GetBucketLocation",
        "s3:GetBucketAcl",
        "s3:GetBucketCORS",
        "s3:GetBucketVersioning",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketPolicy",
        "s3:GetBucketPolicyStatus",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketTagging"
      ]
      Resource = "arn:aws:s3:::*"
    },
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload",
        "s3:GetObjectTorrent",
        "s3:GetObjectVersionTorrent",
        "s3:RestoreObject"
      ]
      Resource = "arn:aws:s3:::*/*"
    }
  ]
}

# Create the Kubernetes service account with IAM role annotation
resource "kubernetes_service_account" "user_sa" {
  metadata {
    name      = "user-sa"
    namespace = kubernetes_namespace.daskhub.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.user_s3_irsa.role_arn
    }
  }

  depends_on = [kubernetes_namespace.daskhub]
}
