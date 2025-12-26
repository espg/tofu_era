# IRSA (IAM Roles for Service Accounts) module
# Creates IAM role for Kubernetes service accounts

locals {
  oidc_provider_id = replace(var.oidc_provider_arn, "/^.*:oidc-provider//", "")
}

# IAM Role for Service Account
resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-${var.namespace}-${var.service_account}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
        }
      }
    }]
  })

  tags = var.tags
}

# Policy from statements
resource "aws_iam_role_policy" "from_statements" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  name = "${var.service_account}-policy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}