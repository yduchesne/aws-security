variable "lab_account_ids" {
  description = "Explicit Dev Lab and Test Lab account IDs; shared with the workload-access root."
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

variable "lab_baseline_aws_profiles" {
  description = "Authenticated AWS CLI profiles with trusted boundary-provisioning access in the Dev Lab and Test Lab accounts."
  type = object({
    dev  = string
    test = string
  })

  validation {
    condition = alltrue([
      for profile in values(var.lab_baseline_aws_profiles) : length(trimspace(profile)) > 0
    ])
    error_message = "lab_baseline_aws_profiles must contain non-empty dev and test AWS CLI profile names."
  }
}

variable "aws_region" {
  description = "AWS Region used by the baseline automation providers."
  type        = string
  default     = "us-east-2"
}

variable "lab_role_boundary_name" {
  description = "Name of the Week 2 lab-role permissions boundary."
  type        = string
  default     = "WorkloadLabRoleBoundary"

  validation {
    condition     = var.lab_role_boundary_name == "WorkloadLabRoleBoundary"
    error_message = "lab_role_boundary_name must remain WorkloadLabRoleBoundary unless the workload-access security design is reviewed with this baseline."
  }
}

variable "lab_role_boundary_path" {
  description = "IAM path of the Week 2 lab-role permissions boundary."
  type        = string
  default     = "/week2/"

  validation {
    condition     = var.lab_role_boundary_path == "/week2/"
    error_message = "lab_role_boundary_path must remain /week2/ unless the workload-access security design is reviewed with this baseline."
  }
}

variable "lab_bucket_name_prefix" {
  description = "S3 bucket-name prefix within the maximum permissions of lab-created roles."
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
  description = "Tags applied to the lab permissions boundaries."
  type        = map(string)

  default = {
    Project      = "aws-security-exercises"
    ManagedBy    = "Terraform"
    Week         = "2"
    ResourceRole = "LabPermissionsBoundary"
  }
}
