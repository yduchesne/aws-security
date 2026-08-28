variable "source_account_id" {
  description = "Twelve-digit ID of the trusted account in which the caller roles are created."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "target_account_id" {
  description = "Twelve-digit ID of the trusting account in which the target role and test buckets are created."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_aws_profile" {
  description = "Local AWS CLI profile with provisioning access to the source account; use an IAM Identity Center profile rather than static credentials."
  type        = string

  validation {
    condition     = length(trimspace(var.source_aws_profile)) > 0
    error_message = "source_aws_profile must not be empty."
  }
}

variable "target_aws_profile" {
  description = "Local AWS CLI profile with provisioning access to the target account; use an IAM Identity Center profile rather than static credentials."
  type        = string

  validation {
    condition     = length(trimspace(var.target_aws_profile)) > 0
    error_message = "target_aws_profile must not be empty."
  }
}

variable "source_operator_role_arn" {
  description = "ARN of the specific IAM or IAM Identity Center provisioned role allowed to assume the two source test roles."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.source_operator_role_arn))
    error_message = "source_operator_role_arn must be an IAM role ARN."
  }
}

variable "aws_region" {
  description = "AWS Region in which the disposable S3 test resources are created."
  type        = string
  default     = "us-east-2"
}

variable "lab_role_boundary_name" {
  description = "Name of the pre-provisioned permissions boundary required on every exercise role."
  type        = string
  default     = "WorkloadLabRoleBoundary"
}

variable "lab_role_boundary_path" {
  description = "IAM path of the pre-provisioned permissions boundary required on every exercise role."
  type        = string
  default     = "/week2/"

  validation {
    condition     = can(regex("^/[A-Za-z0-9.,+@=_/-]+/$", var.lab_role_boundary_path))
    error_message = "lab_role_boundary_path must be an IAM path beginning and ending with a slash."
  }
}

variable "lab_bucket_name_prefix" {
  description = "Bucket-name prefix authorized by WorkloadLabAdministrator."
  type        = string
  default     = "aws-security-week2-"
}

variable "approved_bucket_name" {
  description = "Globally unique name for the S3 bucket the target role may read."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.approved_bucket_name))
    error_message = "approved_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "unrelated_bucket_name" {
  description = "Globally unique name for the S3 bucket used to prove unrelated-resource access is denied."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.unrelated_bucket_name))
    error_message = "unrelated_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "approved_object_key" {
  description = "Key of the object the cross-account target role may read."
  type        = string
  default     = "exercise-1/allowed.txt"

  validation {
    condition     = length(trim(var.approved_object_key, "/")) > 0
    error_message = "approved_object_key must contain a non-empty object key."
  }
}

variable "caller_role_name" {
  description = "Name of the approved source-account caller role."
  type        = string
  default     = "CrossAccountCallerRole"
}

variable "untrusted_role_name" {
  description = "Name of the source-account role used for the negative trust-policy test."
  type        = string
  default     = "UntrustedCrossAccountCallerRole"
}

variable "target_role_name" {
  description = "Name of the target-account read role."
  type        = string
  default     = "CrossAccountReadRole"
}

variable "common_tags" {
  description = "Tags applied to supported exercise resources."
  type        = map(string)

  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Core"
    Exercise   = "1"
  }
}
