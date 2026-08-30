variable "source_account_id" {
  type        = string
  description = "Disposable Dev Lab account ID."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit account ID."
  }
}

variable "source_aws_profile" {
  type        = string
  description = "IAM Identity Center-backed Dev Lab profile."
}

variable "aws_region" {
  type        = string
  description = "Region for the disposable EC2 and S3 resources."
  default     = "us-east-2"
}

variable "ami_id" {
  type        = string
  description = "Optional AMI ID. Null discovers the latest x86_64 Amazon Linux 2023 AMI."
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be null or a valid AMI ID."
  }
}

variable "subnet_id" {
  type        = string
  description = "Optional subnet ID. Null selects an available default subnet."
  default     = null

  validation {
    condition     = var.subnet_id == null || can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be null or a valid subnet ID."
  }
}

variable "instance_type" {
  type        = string
  description = "Small EC2 instance type allowed by the lab administrator permission set."
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.nano"], var.instance_type)
    error_message = "instance_type must be t3.micro or t3.nano."
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

variable "common_tags" {
  type = map(string)
  default = {
    Project    = "aws-security-exercises"
    ManagedBy  = "Terraform"
    Week       = "2"
    Exercise   = "8"
    Curriculum = "Core"
  }
}

variable "target_account_id" {
  description = "Dev/Test lab target account ID used by the shared exercise environment."
  type        = string
}

variable "target_aws_profile" {
  description = "IAM Identity Center-backed target account profile retained for shared environment consistency."
  type        = string
}
