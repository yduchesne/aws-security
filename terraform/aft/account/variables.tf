variable "management_account_id" {
  description = "AWS Organizations management account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "home_region" {
  description = "Control Tower home Region."
  type        = string
  default     = "us-east-2"
}

variable "aft_ou_id" {
  description = "AFT OU ID output by the org_unit root."
  type        = string

  validation {
    condition     = can(regex("^ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}$", var.aft_ou_id))
    error_message = "aft_ou_id must be an AWS Organizations OU ID."
  }
}

variable "aft_ou_name" {
  description = "AFT OU name output by the org_unit root; Account Factory receives it in the required 'Name (ou-id)' format."
  type        = string
  default     = "AFT"
}

variable "aft_control_tower_baseline_arn" {
  description = "Enabled AWSControlTowerBaseline ARN output by the org_unit root."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:controltower:[^:]+:[0-9]{12}:enabledbaseline/[A-Za-z0-9-]+$", var.aft_control_tower_baseline_arn))
    error_message = "aft_control_tower_baseline_arn must be a Control Tower enabled-baseline ARN."
  }
}

variable "account_factory_product_id" {
  description = "Service Catalog product ID for the Control Tower Account Factory product."
  type        = string
}

variable "account_factory_provisioning_artifact_id" {
  description = "Active provisioning artifact ID for the Account Factory product."
  type        = string
}

variable "account_factory_path_id" {
  description = "Optional Service Catalog launch path ID for Account Factory."
  type        = string
  default     = null
  nullable    = true
}

variable "aft_management_account_name" {
  description = "Name of the dedicated AFT management account."
  type        = string
  default     = "AFT-Management"
}

variable "aft_management_account_email" {
  description = "Unique email address for the AFT management account."
  type        = string
  sensitive   = true
}

variable "sso_aft_user_email" {
  description = "Email of the human IAM Identity Center account owner supplied for the AFT management account. This is not an automation identity."
  type        = string
  sensitive   = true
}

variable "sso_aft_user_first_name" {
  description = "First name of the human IAM Identity Center account owner supplied for the AFT management account."
  type        = string
}

variable "sso_aft_user_last_name" {
  description = "Last name of the human IAM Identity Center account owner supplied for the AFT management account."
  type        = string
}

variable "provisioned_product_name" {
  description = "Name of the Service Catalog provisioned product."
  type        = string
  default     = "aft-management-account"
}

variable "common_tags" {
  description = "Tags applied to supported resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "aft-account"
  }
}
