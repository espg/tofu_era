# S3 Module - Scratch bucket for user data

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.cluster_name}-scratch-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "scratch" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-scratch"
    }
  )
}

resource "aws_s3_bucket_versioning" "scratch" {
  bucket = aws_s3_bucket.scratch.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "scratch" {
  count  = var.lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.scratch.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "scratch" {
  bucket = aws_s3_bucket.scratch.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cost & Usage Report (CUR) bucket for Kubecost
# Only created if enable_cur = true
locals {
  cur_bucket_name = "${var.cluster_name}-cur-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "cur" {
  count         = var.enable_cur ? 1 : 0
  bucket        = local.cur_bucket_name
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-cur"
      Purpose = "AWS Cost and Usage Reports for Kubecost"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "cur" {
  count  = var.enable_cur ? 1 : 0
  bucket = aws_s3_bucket.cur[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy to allow AWS Cost & Usage Reports service to write
resource "aws_s3_bucket_policy" "cur" {
  count  = var.enable_cur ? 1 : 0
  bucket = aws_s3_bucket.cur[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCURServiceWrite"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy"
        ]
        Resource = aws_s3_bucket.cur[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceArn"     = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowCURServicePutObject"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cur[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn"     = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Lifecycle configuration for CUR bucket
resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  count  = var.enable_cur && var.cur_retention_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.cur[0].id

  rule {
    id     = "expire-old-cur-data"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cur_retention_days
    }
  }
}

# AWS Cost & Usage Report Definition
# NOTE: CUR reports are managed globally but bucket can be in any region
resource "aws_cur_report_definition" "kubecost" {
  count = var.enable_cur ? 1 : 0

  report_name                = "${var.cluster_name}-kubecost-cur"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur[0].id
  s3_region                  = var.region # Bucket is in cluster region
  s3_prefix                  = "cur"

  additional_artifacts = ["ATHENA"] # Generate Athena-compatible metadata

  # Refresh mode
  refresh_closed_reports = true
  report_versioning      = "OVERWRITE_REPORT"
}
