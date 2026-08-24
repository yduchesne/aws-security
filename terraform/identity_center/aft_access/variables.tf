variable "management_account_id" {
  description = "AWS Organizations management account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "aft_management_account_id" {
  description = "AFT management account ID output by terraform/aft/account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aft_management_account_id))
    error_message = "aft_management_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.aft_management_account_id != var.management_account_id
    error_message = "aft_management_account_id must be distinct from the Organizations management account."
  }
}

variable "home_region" {
  description = "IAM Identity Center Region and Control Tower home Region."
  type        = string
  default     = "us-east-2"
}

variable "sso_aft_user_email" {
  description = "Email/username of the existing human IAM Identity Center user supplied to Account Factory for the AFT management account. This root looks up but does not own the user."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_aft_user_email))
    error_message = "sso_aft_user_email must be a valid email address."
  }
}

variable "privileged_session_duration" {
  description = "Session duration for the AFT platform administration permission set."
  type        = string
  default     = "PT1H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.privileged_session_duration))
    error_message = "privileged_session_duration must be an ISO-8601 duration from PT1H through PT12H."
  }
}

variable "common_tags" {
  description = "Tags applied to supported AFT access resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "identity-center-aft-access"
  }
}
