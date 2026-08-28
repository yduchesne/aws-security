variable "management_account_id" {
  description = "AWS Organizations management account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "home_region" {
  description = "IAM Identity Center Region and Control Tower home Region."
  type        = string
  default     = "us-east-2"
}

variable "sso_identity_store_admin_email" {
  description = "Email of the named human assigned to AWSIdentityStoreAdmins."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_identity_store_admin_email))
    error_message = "sso_identity_store_admin_email must be a valid email address."
  }
}

variable "sso_identity_store_admin_first_name" {
  description = "First name of the named human assigned to AWSIdentityStoreAdmins."
  type        = string
}

variable "sso_identity_store_admin_last_name" {
  description = "Last name of the named human assigned to AWSIdentityStoreAdmins."
  type        = string
}

variable "sso_permission_set_admin_email" {
  description = "Email of the named human assigned to AWSPermissionSetAdmins."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_permission_set_admin_email))
    error_message = "sso_permission_set_admin_email must be a valid email address."
  }
}

variable "sso_permission_set_admin_first_name" {
  description = "First name of the named human assigned to AWSPermissionSetAdmins."
  type        = string
}

variable "sso_permission_set_admin_last_name" {
  description = "Last name of the named human assigned to AWSPermissionSetAdmins."
  type        = string
}

variable "sso_access_assignment_admin_email" {
  description = "Email of the named human assigned to AWSAccessAssignmentAdmins."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_access_assignment_admin_email))
    error_message = "sso_access_assignment_admin_email must be a valid email address."
  }
}

variable "sso_access_assignment_admin_first_name" {
  description = "First name of the named human assigned to AWSAccessAssignmentAdmins."
  type        = string
}

variable "sso_access_assignment_admin_last_name" {
  description = "Last name of the named human assigned to AWSAccessAssignmentAdmins."
  type        = string
}

variable "sso_lab_admin_email" {
  description = "Email of the dedicated named human who administers the Week 2 lab permissions boundary."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_lab_admin_email))
    error_message = "sso_lab_admin_email must be a valid email address."
  }
}

variable "sso_lab_admin_first_name" {
  description = "First name of the dedicated Week 2 lab baseline administrator."
  type        = string

  validation {
    condition     = length(trimspace(var.sso_lab_admin_first_name)) > 0
    error_message = "sso_lab_admin_first_name must not be empty."
  }
}

variable "sso_lab_admin_last_name" {
  description = "Last name of the dedicated Week 2 lab baseline administrator."
  type        = string

  validation {
    condition     = length(trimspace(var.sso_lab_admin_last_name)) > 0
    error_message = "sso_lab_admin_last_name must not be empty."
  }
}

variable "privileged_session_duration" {
  description = "Session duration for privileged Identity Center permission sets."
  type        = string
  default     = "PT1H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.privileged_session_duration))
    error_message = "privileged_session_duration must be an ISO-8601 duration from PT1H through PT12H."
  }
}

variable "common_tags" {
  description = "Tags applied to supported Identity Center resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "identity-center"
  }
}
