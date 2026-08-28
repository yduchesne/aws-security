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
    Curriculum = "Optional"
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
variable "source_operator_role_arn" {
  description = "IAM Identity Center-provisioned source operator role ARN."
  type        = string
}
