# ACM Certificate Module
# Creates and validates SSL/TLS certificates for JupyterHub

# Request ACM certificate with DNS validation
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Request wildcard certificate to cover subdomains
  subject_alternative_names = var.enable_wildcard ? ["*.${var.domain_name}"] : []

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Wait for certificate validation (only if auto_validate is true)
# For external DNS: Set auto_validate = false, add DNS records manually, then set to true
resource "aws_acm_certificate_validation" "cert" {
  count = var.auto_validate ? 1 : 0

  certificate_arn = aws_acm_certificate.cert.arn

  timeouts {
    create = var.validation_timeout
  }
}

# Output for manual DNS validation
locals {
  # Extract validation options for easy reference
  validation_options = [
    for dvo in aws_acm_certificate.cert.domain_validation_options : {
      domain_name           = dvo.domain_name
      resource_record_name  = dvo.resource_record_name
      resource_record_type  = dvo.resource_record_type
      resource_record_value = dvo.resource_record_value
    }
  ]
}
