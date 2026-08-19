# Contains variable declarations for variables that are injected in other Terraform files under this directory.
# The variables flagged as sensitive are meant to be injected with values from environment variables.
# For the environment variable names, The convention is as follows: TF_VAR_<variable_name>
#
# Examples:
# TF_VAR_security_tooling_account_email="security-tooling@example.com"
# TF_VAR_log_archive_account_email="log-archive@example.com"

# Added to ensure that the bootstrap is run againt the management account.
# Provide the following environment variable, which will be injected into this
# TF variable:
#   TF_VAR_management_account_id=<your_management_account_id>
variable "management_account_id" {
  description = "Expected AWS Organizations management account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

# Tagging
variable "common_tags" {
  description = "Tags applied to all supported AWS resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "bootstrap"
  }
}

variable "home_region" {
  description = "AWS home region for the Control Tower landing zone."
  type        = string
  default     = "us-east-2"
}

variable "governed_regions" {
  description = "AWS regions governed by Control Tower."
  type        = list(string)
  default     = ["us-east-2"]
}

variable "security_ou_name" {
  description = "Name of the root-level Security OU."
  type        = string
  default     = "Security"
}

variable "control_tower_version" {
  description = "Control Tower landing zone version."
  type        = string
  default     = "4.0"
}

variable "security_tooling_account_email" {
  description = "Email address for the Security Tooling account."
  type        = string
  sensitive   = true
}

variable "log_archive_account_email" {
  description = "Email address for the Log Archive account."
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "Retention period for centralized Control Tower logs."
  type        = number
}

variable "access_log_retention_days" {
  description = "Retention period for access logging."
  type        = number
}


variable "monthly_budget_amount" {
  description = "Monthly AWS budget for the management/payer account."
  type        = number
  default     = 50

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than zero."
  }
}

variable "budget_notification_emails" {
  description = "Email addresses that receive AWS Budget notifications."
  type        = list(string)

  validation {
    condition     = length(var.budget_notification_emails) > 0
    error_message = "At least one budget notification email must be configured."
  }
}
