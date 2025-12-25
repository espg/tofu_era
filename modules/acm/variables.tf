# ACM Module Variables

variable "domain_name" {
  description = "Domain name for the SSL/TLS certificate"
  type        = string
}

variable "enable_wildcard" {
  description = "Include wildcard (*.domain) as subject alternative name"
  type        = bool
  default     = true
}

variable "auto_validate" {
  description = "Automatically wait for certificate validation. Set to false for manual DNS validation with external DNS providers."
  type        = bool
  default     = false
}

variable "validation_timeout" {
  description = "Timeout for certificate validation (e.g., '45m'). Only applies if auto_validate is true."
  type        = string
  default     = "45m"
}

variable "tags" {
  description = "Tags to apply to ACM certificate"
  type        = map(string)
  default     = {}
}
