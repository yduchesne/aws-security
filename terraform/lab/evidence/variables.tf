variable "management_account_id" {
  description = "AWS Organizations management account ID in which the organization trail is created."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "log_archive_account_id" {
  description = "Control Tower Log Archive account ID in which the evidence bucket is created."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be a 12-digit AWS account ID."
  }
}

variable "lab_account_ids" {
  description = "Dev Lab and Test Lab account IDs whose evidence prefixes lab users may read."
  type = object({
    dev  = string
    test = string
  })

  validation {
    condition = (
      can(regex("^[0-9]{12}$", var.lab_account_ids.dev)) &&
      can(regex("^[0-9]{12}$", var.lab_account_ids.test)) &&
      var.lab_account_ids.dev != var.lab_account_ids.test
    )
    error_message = "lab_account_ids must contain distinct 12-digit dev and test account IDs."
  }
}

variable "home_region" {
  description = "Control Tower home Region used for the customer-managed organization trail."
  type        = string
  default     = "us-east-2"
}

variable "management_aws_profile" {
  description = "AWS CLI profile for the temporary ct-bootstrap identity in the Organizations management account."
  type        = string
  default     = "ct-bootstrap"
}

variable "log_archive_execution_role_name" {
  description = "Existing Control Tower execution role assumed by ct-bootstrap to create the evidence bucket in Log Archive."
  type        = string
  default     = "AWSControlTowerExecution"
}

variable "lab_bucket_name_prefix" {
  description = "S3 bucket-name prefix whose object data events are captured by the trail."
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

variable "evidence_retention_days" {
  description = "Number of days before current and noncurrent evidence objects expire."
  type        = number
  default     = 30

  validation {
    condition     = var.evidence_retention_days >= 1 && var.evidence_retention_days <= 365
    error_message = "evidence_retention_days must be between 1 and 365."
  }
}

variable "common_tags" {
  description = "Tags applied to project-owned evidence resources."
  type        = map(string)
  default = {
    Project   = "aws-security"
    ManagedBy = "Terraform"
    Purpose   = "LabEvidence"
  }
}
