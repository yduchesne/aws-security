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

variable "sso_lab_admin_email" {
  description = "Email of the existing lab baseline administrator created by the parent Identity Center root."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sso_lab_admin_email))
    error_message = "sso_lab_admin_email must be a valid email address."
  }
}

variable "lab_account_ids" {
  description = "Explicit allowlist of the Dev Lab and Test Lab account IDs eligible for WorkloadLabAdministrator assignments; leave empty until both accounts exist."
  type        = map(string)
  default     = {}

  validation {
    condition = (
      length(var.lab_account_ids) == 0 ||
      (
        toset(keys(var.lab_account_ids)) == toset(["dev", "test"]) &&
        alltrue([for account_id in values(var.lab_account_ids) : can(regex("^[0-9]{12}$", account_id))]) &&
        length(toset(values(var.lab_account_ids))) == 2
      )
    )
    error_message = "lab_account_ids must be empty or contain distinct 12-digit dev and test account IDs."
  }
}

variable "lab_role_path_prefix" {
  description = "IAM path prefix under which bounded lab roles may be created and managed."
  type        = string
  default     = "/week2/"

  validation {
    condition = (
      can(regex("^/[A-Za-z0-9.,+@=_/-]+/$", var.lab_role_path_prefix)) &&
      startswith(var.lab_role_path_prefix, "/week2/")
    )
    error_message = "lab_role_path_prefix must remain within /week2/ and end with a slash."
  }
}

variable "lab_role_boundary_name" {
  description = "Name of the pre-provisioned customer-managed permissions boundary required on every lab-created role."
  type        = string
  default     = "WorkloadLabRoleBoundary"

  validation {
    condition     = var.lab_role_boundary_name == "WorkloadLabRoleBoundary"
    error_message = "lab_role_boundary_name must remain WorkloadLabRoleBoundary unless the security design and trusted baseline are reviewed together."
  }
}

variable "lab_role_boundary_path" {
  description = "IAM path of the pre-provisioned customer-managed lab-role permissions boundary."
  type        = string
  default     = "/week2/"

  validation {
    condition     = var.lab_role_boundary_path == "/week2/"
    error_message = "lab_role_boundary_path must remain /week2/ unless the security design and trusted baseline are reviewed together."
  }
}

variable "lab_bucket_name_prefix" {
  description = "Required globally scoped bucket-name prefix for resources managed by WorkloadLabAdministrator."
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
      contains(["viewers", "security_auditors", "developers", "test_operators", "production_operators", "lab_administrators"], assignment.group_key) &&
      contains(["view_only", "security_audit", "developer", "test_operator", "production_operator", "lab_administrator"], assignment.permission_set_key)
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
