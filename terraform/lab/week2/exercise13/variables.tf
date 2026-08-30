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

variable "management_account_id" {
  type        = string
  description = "AWS Organizations management account ID used for SCP administration."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
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
  description = "AWS Region for the Dev Lab fixture and Organizations provider."
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
    condition     = can(regex("^/[A-Za-z0-9.,+@=_/-]+/$", var.lab_role_boundary_path))
    error_message = "lab_role_boundary_path must be an IAM path beginning and ending with a slash."
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

variable "scp_deny_enabled" {
  type        = bool
  description = "Whether to attach the exercise SCP explicit deny to the Dev Lab account."
  default     = false
}

variable "scp_deny_actions" {
  type        = list(string)
  description = "S3 actions explicitly denied by the disposable SCP fixture."
  default     = ["s3:PutObject"]

  validation {
    condition = (
      length(var.scp_deny_actions) > 0 &&
      alltrue([for action in var.scp_deny_actions : contains([
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
      ], action)])
    )
    error_message = "scp_deny_actions must be non-empty and contain only the eight approved Week 2 S3 actions."
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
    Exercise   = "13"
  }
}
