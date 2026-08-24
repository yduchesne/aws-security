variable "management_account_id" {
  description = "AWS Organizations management account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "organization_root_id" {
  description = "Organizations root ID output by the completed bootstrap root."
  type        = string

  validation {
    condition     = can(regex("^r-[a-z0-9]{4,32}$", var.organization_root_id))
    error_message = "organization_root_id must be an AWS Organizations root ID."
  }
}

variable "landing_zone_arn" {
  description = "ARN of the existing, completed Control Tower landing zone."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:controltower:[^:]+:[0-9]{12}:landingzone/[A-Za-z0-9-]+$", var.landing_zone_arn))
    error_message = "landing_zone_arn must be a Control Tower landing-zone ARN."
  }
}

variable "landing_zone_drift_status" {
  description = "Drift status output by the bootstrap root."
  type        = string

  validation {
    condition     = var.landing_zone_drift_status == "IN_SYNC"
    error_message = "The existing Control Tower landing zone must report IN_SYNC before creating or changing the workload OU hierarchy."
  }
}

variable "home_region" {
  description = "Control Tower home Region."
  type        = string
  default     = "us-east-2"
}

variable "workloads_ou_name" {
  description = "Name of the root-level workloads OU."
  type        = string
  default     = "Workloads"

  validation {
    condition     = length(trimspace(var.workloads_ou_name)) > 0
    error_message = "workloads_ou_name must not be empty."
  }
}

variable "environment_ou_names" {
  description = "Names of the environment OUs created directly below the workloads OU."
  type        = map(string)

  default = {
    dev  = "Dev"
    test = "Test"
    prod = "Prod"
  }

  validation {
    condition = (
      toset(keys(var.environment_ou_names)) == toset(["dev", "test", "prod"]) &&
      alltrue([for name in values(var.environment_ou_names) : length(trimspace(name)) > 0]) &&
      length(toset(values(var.environment_ou_names))) == length(values(var.environment_ou_names))
    )
    error_message = "environment_ou_names must contain exactly dev, test, and prod with distinct, non-empty OU names."
  }
}

variable "control_tower_baseline_version" {
  description = "AWSControlTowerBaseline version compatible with this landing-zone version."
  type        = string
  default     = "5.0"

  validation {
    condition     = var.control_tower_baseline_version == "5.0"
    error_message = "control_tower_baseline_version must remain 5.0 for the current Control Tower landing zone. Review AWS baseline compatibility before changing this invariant."
  }
}

variable "identity_center_enabled_baseline_arn" {
  description = "ARN of the IdentityCenterBaseline instance enabled by the existing landing zone."
  type        = string

  validation {
    condition = can(regex(
      "^arn:[^:]+:controltower:[^:]+:[0-9]{12}:enabledbaseline/[A-Za-z0-9-]+$",
      var.identity_center_enabled_baseline_arn
    ))
    error_message = "identity_center_enabled_baseline_arn must be a Control Tower enabled-baseline ARN."
  }
}

variable "common_tags" {
  description = "Tags applied to supported resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "workload-org-units"
  }
}
