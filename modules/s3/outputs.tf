# S3 module outputs

output "bucket_name" {
  description = "Name of the S3 scratch bucket"
  value       = aws_s3_bucket.scratch.id
}

output "bucket_arn" {
  description = "ARN of the S3 scratch bucket"
  value       = aws_s3_bucket.scratch.arn
}

output "cur_bucket_name" {
  description = "Name of the CUR S3 bucket (if enabled)"
  value       = var.enable_cur ? aws_s3_bucket.cur[0].id : null
}

output "cur_bucket_arn" {
  description = "ARN of the CUR S3 bucket (if enabled)"
  value       = var.enable_cur ? aws_s3_bucket.cur[0].arn : null
}

output "cur_report_name" {
  description = "Name of the Cost & Usage Report (if enabled)"
  value       = var.enable_cur ? aws_cur_report_definition.kubecost[0].report_name : null
}
