variable "source_account_id" {
  description = "Account containing the approved and unapproved source roles."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "target_account_id" {
  description = "Account containing the target role."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_aws_profile" {
  description = "IAM Identity Center-backed profile for the source account."
  type        = string
  validation {
    condition     = length(trimspace(var.source_aws_profile)) > 0
    error_message = "source_aws_profile must not be empty."
  }
}

variable "target_aws_profile" {
  description = "IAM Identity Center-backed profile for the target account."
  type        = string
  validation {
    condition     = length(trimspace(var.target_aws_profile)) > 0
    error_message = "target_aws_profile must not be empty."
  }
}

variable "source_operator_role_arn" {
  description = "Exact IAM role ARN allowed to assume both source test roles."
  type        = string
  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.source_operator_role_arn))
    error_message = "source_operator_role_arn must be an IAM role ARN."
  }
}

variable "trust_mode" {
  description = "Target trust mode: account trusts the source account root; role trusts only the approved role."
  type        = string
  default     = "account"
  validation {
    condition     = contains(["account", "role"], var.trust_mode)
    error_message = "trust_mode must be either account or role."
  }
}

variable "aws_region" {
  description = "Region used for the disposable exercise resources."
  type        = string
  default     = "us-east-2"
}

variable "lab_role_boundary_name" {
  description = "Pre-provisioned boundary required by every exercise role."
  type        = string
  default     = "WorkloadLabRoleBoundary"
}

variable "lab_role_boundary_path" {
  description = "Path of the pre-provisioned lab role boundary."
  type        = string
  default     = "/week2/"
}

variable "approved_role_name" {
  description = "Source role approved by the hardened target trust policy."
  type        = string
  default     = "ApprovedAutomationRole"
}

variable "unapproved_role_name" {
  description = "Source role used to demonstrate the broader account trust."
  type        = string
  default     = "UnapprovedRole"
}

variable "target_role_name" {
  description = "Target role whose trust policy is changed during the exercise."
  type        = string
  default     = "TrustHardeningTargetRole"
}

variable "common_tags" {
  description = "Tags applied to supported exercise resources."
  type        = map(string)
  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Core"
    Exercise   = "2"
  }
}
