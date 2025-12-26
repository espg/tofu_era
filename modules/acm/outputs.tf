# ACM Module Outputs

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.cert.arn
}

output "certificate_status" {
  description = "Status of the ACM certificate validation"
  value       = aws_acm_certificate.cert.status
}

output "certificate_domain" {
  description = "Domain name of the certificate"
  value       = aws_acm_certificate.cert.domain_name
}

output "dns_validation_records" {
  description = "DNS records needed for certificate validation. Add these to your DNS provider."
  value       = local.validation_options
}

output "validation_instructions" {
  description = "Instructions for manual DNS validation"
  value = var.auto_validate ? "Certificate validation is automatic." : <<-EOT

    ============================================
    ACM Certificate DNS Validation Required
    ============================================

    Add the following DNS records to your DNS provider:

    ${join("\n\n", [for opt in local.validation_options : <<-RECORD
    Domain: ${opt.domain_name}
    Type:   ${opt.resource_record_type}
    Name:   ${opt.resource_record_name}
    Value:  ${opt.resource_record_value}
    RECORD
])}

    After adding the DNS records:
    1. Wait 5-10 minutes for DNS propagation
    2. Set 'acm_auto_validate = true' in terraform.tfvars
    3. Run 'make apply' again to complete validation

    Or check validation status:
    aws acm describe-certificate --certificate-arn ${aws_acm_certificate.cert.arn} --region ${data.aws_region.current.name}

    ============================================
  EOT
}

# Data source to get current region
data "aws_region" "current" {}
