variable "source_account_id" {
  type        = string
  description = "Disposable Dev Lab source account ID."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "target_account_id" {
  type        = string
  description = "Disposable Test Lab target account ID."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }
}

variable "management_account_id" {
  type        = string
  description = "Organizations management account ID used only to administer the optional SCP."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_aws_profile" {
  type        = string
  description = "IAM Identity Center-backed AWS profile for the Dev Lab account."

  validation {
    condition     = length(trimspace(var.source_aws_profile)) > 0
    error_message = "source_aws_profile must not be empty."
  }
}

variable "target_aws_profile" {
  type        = string
  description = "IAM Identity Center-backed AWS profile for the Test Lab account."

  validation {
    condition     = length(trimspace(var.target_aws_profile)) > 0
    error_message = "target_aws_profile must not be empty."
  }
}

variable "management_aws_profile" {
  type        = string
  description = "Approved AWS profile for the Organizations management account."

  validation {
    condition     = length(trimspace(var.management_aws_profile)) > 0
    error_message = "management_aws_profile must not be empty."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS Region used by the disposable fixtures and Organizations provider."
  default     = "us-east-2"
}

variable "lab_role_boundary_name" {
  type        = string
  description = "Name of the pre-provisioned permissions boundary required on every fixture role."
  default     = "WorkloadLabRoleBoundary"
}

variable "lab_role_boundary_path" {
  type        = string
  description = "IAM path of the pre-provisioned permissions boundary."
  default     = "/week2/"

  validation {
    condition     = var.lab_role_boundary_path == "/week2/"
    error_message = "lab_role_boundary_path is fixed to /week2/ for the lab baseline boundary."
  }
}

variable "external_id" {
  type        = string
  description = "ExternalId identifier required by the negative/positive trust-condition fixture; it is not a secret."

  validation {
    condition     = length(trimspace(var.external_id)) > 0
    error_message = "external_id must not be empty."
  }
}

variable "scp_deny_enabled" {
  type        = bool
  description = "Whether to attach the disposable AssumeRole SCP deny to the source account."
  default     = false
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to supported exercise resources."

  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Core"
    Exercise   = "15"
  }
}
