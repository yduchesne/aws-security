variable "source_account_id" {
  type        = string
  description = "Disposable Dev Lab account ID."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
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

variable "aws_region" {
  type        = string
  description = "AWS Region for the Dev Lab fixture."
  default     = "us-east-2"
}

variable "lab_role_boundary_name" {
  type        = string
  description = "Name of the pre-provisioned permissions boundary required on the exercise role."
  default     = "WorkloadLabRoleBoundary"
}

variable "lab_role_boundary_path" {
  type        = string
  description = "IAM path of the pre-provisioned permissions boundary."
  default     = "/week2/"

  validation {
    condition     = var.lab_role_boundary_path == "/week2/"
    error_message = "lab_role_boundary_path must remain /week2/ unless the security design and trusted baseline are reviewed together."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to supported exercise resources."

  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Optional"
    Exercise   = "14"
  }
}
