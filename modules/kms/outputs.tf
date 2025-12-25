output "key_id" {
  description = "KMS key ID (ARN)"
  value       = aws_kms_key.eks.arn
}

output "key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.eks.arn
}

output "alias_name" {
  description = "KMS key alias name"
  value       = aws_kms_alias.eks.name
}
