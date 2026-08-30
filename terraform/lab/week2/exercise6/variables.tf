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

variable "lab_bucket_name_prefix" {
  description = "Globally scoped bucket-name prefix authorized by WorkloadLabAdministrator."
  type        = string
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

variable "target_account_id" {
  description = "Dev/Test lab target account ID used by the exercise context."
  type        = string
}
variable "target_aws_profile" {
  description = "IAM Identity Center-backed target account profile."
  type        = string
}
