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

variable "test_user1_email" {
  description = "Email address and user name for the first manually operated Identity Center test user."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.test_user1_email))
    error_message = "test_user1_email must be a valid email address."
  }
}

variable "test_user1_first_name" {
  description = "First name of the first Identity Center test user."
  type        = string

  validation {
    condition     = length(trimspace(var.test_user1_first_name)) > 0
    error_message = "test_user1_first_name must not be empty."
  }
}

variable "test_user1_last_name" {
  description = "Last name of the first Identity Center test user."
  type        = string

  validation {
    condition     = length(trimspace(var.test_user1_last_name)) > 0
    error_message = "test_user1_last_name must not be empty."
  }
}

variable "test_user2_email" {
  description = "Email address and user name for the second manually operated Identity Center test user."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.test_user2_email))
    error_message = "test_user2_email must be a valid email address."
  }
}

variable "test_user2_first_name" {
  description = "First name of the second Identity Center test user."
  type        = string

  validation {
    condition     = length(trimspace(var.test_user2_first_name)) > 0
    error_message = "test_user2_first_name must not be empty."
  }
}

variable "test_user2_last_name" {
  description = "Last name of the second Identity Center test user."
  type        = string

  validation {
    condition     = length(trimspace(var.test_user2_last_name)) > 0
    error_message = "test_user2_last_name must not be empty."
  }
}

variable "test_operator_allowed_actions" {
  description = "Explicit write actions added to WorkloadTestOperator. Keep empty until Test operational requirements are reviewed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for action in var.test_operator_allowed_actions :
      !strcontains(action, "*") &&
      !can(regex("^(account|controltower|iam|identitystore|organizations|sso|sts):", lower(action)))
    ])
    error_message = "Test operator actions must be explicit and must not grant identity, Organizations, Control Tower, account administration, or role assumption."
  }
}

variable "production_operator_allowed_actions" {
  description = "Explicit write actions added to WorkloadProductionOperator. Keep empty until Prod operational requirements are reviewed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for action in var.production_operator_allowed_actions :
      !strcontains(action, "*") &&
      !can(regex("^(account|controltower|iam|identitystore|organizations|sso|sts):", lower(action)))
    ])
    error_message = "Production operator actions must be explicit and must not grant identity, Organizations, Control Tower, account administration, or role assumption."
  }
}

variable "account_assignments" {
  description = "Approved workload group assignments, keyed by a stable descriptive identifier. Keep empty until AFT-created account IDs are known."
  type = map(object({
    account_id         = string
    environment        = string
    group_key          = string
    permission_set_key = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for assignment in values(var.account_assignments) :
      can(regex("^[0-9]{12}$", assignment.account_id)) &&
      contains(["dev", "test", "prod"], assignment.environment) &&
      contains(["viewers", "security_auditors", "developers", "test_operators", "production_operators"], assignment.group_key) &&
      contains(["view_only", "security_audit", "developer", "test_operator", "production_operator"], assignment.permission_set_key)
    ])
    error_message = "Each assignment must contain a 12-digit account ID and known environment, group, and permission-set keys."
  }

  validation {
    condition = length(distinct([
      for assignment in values(var.account_assignments) :
      "${assignment.account_id}:${assignment.group_key}:${assignment.permission_set_key}"
    ])) == length(var.account_assignments)
    error_message = "account_assignments must not contain duplicate account, group, and permission-set combinations."
  }
}

variable "common_tags" {
  description = "Tags applied to supported Identity Center resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "identity-center-workload-access"
  }
}
