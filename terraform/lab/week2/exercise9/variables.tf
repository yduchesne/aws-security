variable "source_account_id" {
  type        = string
  description = "Disposable lab account ID."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "account_id must be a 12-digit account ID."
  }
}
variable "source_aws_profile" {
  type        = string
  description = "IAM Identity Center-backed AWS profile."
}
variable "aws_region" {
  type    = string
  default = "us-east-2"
}
variable "common_tags" {
  type = map(string)
  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Core"
  }
}
variable "oidc_url" {
  description = "HTTPS issuer URL for the trusted OIDC provider."
  type        = string

  validation {
    condition     = can(regex("^https://[^/[:space:]]+(/[^[:space:]]*)?$", var.oidc_url))
    error_message = "oidc_url must be an HTTPS OIDC issuer URL."
  }
}

variable "oidc_thumbprint" {
  description = "Lowercase SHA-1 thumbprint for the OIDC provider's TLS certificate chain."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{40}$", var.oidc_thumbprint))
    error_message = "oidc_thumbprint must be a 40-character hexadecimal SHA-1 thumbprint."
  }
}

variable "oidc_subject" {
  description = "Exact OIDC subject claim trusted by the exercise role."
  type        = string

  validation {
    condition     = length(trimspace(var.oidc_subject)) > 0 && !strcontains(var.oidc_subject, "*")
    error_message = "oidc_subject must be non-empty and must not contain wildcards."
  }
}

variable "target_account_id" {
  description = "Dev/Test lab target account ID used by the exercise context."
  type        = string
}
variable "target_aws_profile" {
  description = "IAM Identity Center-backed target account profile."
  type        = string
}
