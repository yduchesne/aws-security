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
  type        = string
  description = "The name of the IAM policy to use as a permissions boundary."
  default     = "WorkloadLabRoleBoundary"
}

variable "lab_role_boundary_path" {
  type        = string
  description = "The path of the IAM policy to use as a permissions boundary."
  default     = "/week2/"
}
