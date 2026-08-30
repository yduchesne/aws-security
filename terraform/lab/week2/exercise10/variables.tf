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
  description = "AWS Region for the analyzer and S3 fixture."
  default     = "us-east-2"
}

variable "external_account_id" {
  type        = string
  description = "Test Lab account ID used as the intentionally external S3 principal."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.external_account_id))
    error_message = "external_account_id must be a 12-digit AWS account ID."
  }
}

variable "lab_bucket_name_prefix" {
  type        = string
  description = "Bucket-name prefix authorized by WorkloadLabAdministrator."
  default     = "aws-security-week2-"

  validation {
    condition = (
      can(regex("^aws-security-week2-[a-z0-9-]*$", var.lab_bucket_name_prefix)) &&
      endswith(var.lab_bucket_name_prefix, "-") &&
      length(var.lab_bucket_name_prefix) <= 40
    )
    error_message = "lab_bucket_name_prefix must begin with aws-security-week2-, end with a hyphen, and be no longer than 40 characters."
  }
}

variable "bucket_name" {
  type        = string
  description = "Globally unique name for the disposable S3 fixture bucket."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "external_grant_enabled" {
  type        = bool
  description = "Whether to publish the intentional cross-account S3 policy statement."
  default     = true
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
    condition     = can(regex("^/[A-Za-z0-9.,+@=_/-]+/$", var.lab_role_boundary_path))
    error_message = "lab_role_boundary_path must be an IAM path beginning and ending with a slash."
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
    Exercise   = "10"
  }
}
