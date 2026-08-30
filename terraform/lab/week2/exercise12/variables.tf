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

variable "unused_access_age" {
  type        = number
  description = "Number of days of inactivity before IAM Access Analyzer reports unused access."
  default     = 1

  validation {
    condition     = var.unused_access_age >= 1 && var.unused_access_age <= 180
    error_message = "unused_access_age must be between 1 and 180 days."
  }
}

variable "common_tags" {
  type = map(string)
  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Curriculum = "Optional"
    Exercise   = "12"
  }
}
