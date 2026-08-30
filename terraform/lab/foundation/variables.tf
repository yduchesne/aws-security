variable "management_account_id" {
  description = "AWS Organizations management account ID from which the Dev Lab execution role is assumed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "lab_account_ids" {
  description = "Dev Lab and Test Lab account IDs; this root currently provisions networking only in Dev Lab."
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
  description = "Control Tower home Region and Region for the Dev Lab foundation network."
  type        = string
  default     = "us-east-2"
}

variable "management_aws_profile" {
  description = "Temporary ct-bootstrap AWS CLI profile used to assume into Dev Lab."
  type        = string
  default     = "ct-bootstrap"
}

variable "lab_execution_role_name" {
  description = "Existing Control Tower role assumed in Dev Lab for initial foundation provisioning."
  type        = string
  default     = "AWSControlTowerExecution"
}

variable "dev_lab_vpc_cidr" {
  description = "CIDR for the dedicated Dev Lab exercise VPC. Review for overlap before apply."
  type        = string
  default     = "10.80.0.0/16"

  validation {
    condition     = can(cidrhost(var.dev_lab_vpc_cidr, 0))
    error_message = "dev_lab_vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "dev_lab_public_subnet_cidr" {
  description = "CIDR for the public exercise subnet inside the Dev Lab exercise VPC."
  type        = string
  default     = "10.80.0.0/24"

  validation {
    condition     = can(cidrhost(var.dev_lab_public_subnet_cidr, 0))
    error_message = "dev_lab_public_subnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "common_tags" {
  description = "Tags applied to the project-owned Dev Lab foundation resources."
  type        = map(string)
  default = {
    Project   = "aws-security"
    ManagedBy = "Terraform"
    Purpose   = "LabExercises"
  }
}
