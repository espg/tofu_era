# OpenTofu Native State Encryption Configuration
# This file configures encryption for state, plan files, and outputs
# OpenTofu 1.7+ provides native encryption without external tools

# State encryption configuration
# TEMPORARILY DISABLED: The encryption configuration needs to be restructured
# Uncomment and configure properly when ready to enable state encryption
# terraform {
#   encryption {
#     # Method 1: Using AWS KMS for state encryption (Recommended for production)
#     method "aes_gcm" "aws_kms" {
#       keys = key_provider.aws_kms.jupyterhub_state_key
#     }
#
#     # Method 2: Local passphrase encryption (for development/testing)
#     # Uncomment to use passphrase-based encryption instead of KMS
#     # method "aes_gcm" "passphrase" {
#     #   keys = key_provider.pbkdf2.passphrase
#     # }
#
#     # State encryption configuration
#     state {
#       # Use AWS KMS method by default
#       method = method.aes_gcm.aws_kms
#
#       # For development, switch to passphrase:
#       # method = method.aes_gcm.passphrase
#
#       # Enforce encryption - prevents unencrypted state writes
#       enforced = true
#     }
#
#     # Plan file encryption
#     plan {
#       method = method.aes_gcm.aws_kms
#       # method = method.aes_gcm.passphrase  # For development
#
#       enforced = true
#     }
#
#     # Remote state data sources encryption
#     remote_state_data_sources {
#       default {
#         method = method.aes_gcm.aws_kms
#         # method = method.aes_gcm.passphrase  # For development
#       }
#     }
#   }
# }

# AWS KMS Key Provider for production use
# NOTE: These key_provider blocks should be inside terraform { encryption { } } block
# They are commented out until encryption is properly configured
# key_provider "aws_kms" "jupyterhub" {
#   region = var.region
#
#   # KMS key configuration for state encryption
#   key_spec = "AES_256"
#
#   # Key alias for easy identification
#   key "jupyterhub_state_key" {
#     # Use environment-specific KMS key
#     kms_key_id = "alias/tofu-state-${var.cluster_name}-${var.environment}"
#
#     # Alternative: Use a specific KMS key ARN
#     # kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
#
#     # Alternative: Create and use a new KMS key (managed by OpenTofu)
#     # kms_key_id = aws_kms_key.terraform_state.id
#   }
# }

# Passphrase-based Key Provider for development
# The passphrase should be stored securely and never committed to version control
# key_provider "pbkdf2" "passphrase" {
#   passphrase = var.encryption_passphrase  # Set via TF_VAR_encryption_passphrase env var
#
#   # Optional: Use a file-based passphrase (more secure than env var)
#   # passphrase_file = "${path.module}/.encryption_passphrase"
#
#   # Key derivation configuration
#   iteration_count = 100000  # Number of iterations for key derivation
#   key_length      = 32       # Key length in bytes (32 = 256 bits)
#   salt_length     = 16       # Salt length in bytes
# }

# Variables for encryption configuration
variable "encryption_passphrase" {
  description = "Passphrase for state encryption (development only)"
  type        = string
  sensitive   = true
  default     = "" # Must be set via environment variable TF_VAR_encryption_passphrase
}

# Optional: Create a dedicated KMS key for state encryption
# Uncomment this resource if you want OpenTofu to manage the KMS key
# resource "aws_kms_key" "terraform_state" {
#   description = "KMS key for OpenTofu state encryption - ${var.cluster_name}-${var.environment}"
#
#   # Key rotation for security
#   enable_key_rotation = true
#
#   # Key policy allowing OpenTofu to use the key
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "Enable IAM User Permissions"
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#         }
#         Action   = "kms:*"
#         Resource = "*"
#       },
#       {
#         Sid    = "Allow OpenTofu State Encryption"
#         Effect = "Allow"
#         Principal = {
#           AWS = data.aws_caller_identity.current.arn
#         }
#         Action = [
#           "kms:Decrypt",
#           "kms:Encrypt",
#           "kms:GenerateDataKey",
#           "kms:DescribeKey"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
#
#   tags = merge(local.common_tags, {
#     Name    = "tofu-state-${var.cluster_name}-${var.environment}"
#     Purpose = "OpenTofu state encryption"
#   })
# }
#
# resource "aws_kms_alias" "terraform_state" {
#   name          = "alias/tofu-state-${var.cluster_name}-${var.environment}"
#   target_key_id = aws_kms_key.terraform_state.key_id
# }