locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.current.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]

  test_users = {
    user1 = {
      email      = var.test_user1_email
      first_name = var.test_user1_first_name
      last_name  = var.test_user1_last_name
    }
    user2 = {
      email      = var.test_user2_email
      first_name = var.test_user2_first_name
      last_name  = var.test_user2_last_name
    }
  }

  groups = {
    viewers = {
      display_name = "WorkloadViewers"
      description  = "Provides approved view-only access to workload accounts."
    }
    security_auditors = {
      display_name = "WorkloadSecurityAuditors"
      description  = "Provides approved security-audit access to workload accounts."
    }
    developers = {
      display_name = "WorkloadDevelopers"
      description  = "Provides development capabilities in approved Dev workload accounts only."
    }
    test_operators = {
      display_name = "WorkloadTestOperators"
      description  = "Provides explicitly approved operational capabilities in Test workload accounts only."
    }
    production_operators = {
      display_name = "WorkloadProductionOperators"
      description  = "Provides explicitly approved operational capabilities in Prod workload accounts only."
    }
  }

  permission_sets = {
    view_only = {
      name               = "WorkloadViewOnly"
      description        = "View-only workload access without write permissions."
      session_duration   = "PT4H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
    }
    security_audit = {
      name               = "WorkloadSecurityAudit"
      description        = "Security configuration and compliance audit access without remediation writes."
      session_duration   = "PT2H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SecurityAudit"
    }
    developer = {
      name               = "WorkloadDeveloper"
      description        = "Development access bounded away from identity, organization, and governance administration."
      session_duration   = "PT2H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
    }
    test_operator = {
      name               = "WorkloadTestOperator"
      description        = "Read-only Test access plus explicitly configured operational actions."
      session_duration   = "PT1H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
    }
    production_operator = {
      name               = "WorkloadProductionOperator"
      description        = "View-only Prod access plus explicitly configured operational actions."
      session_duration   = "PT1H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
    }
  }

  elevated_permission_set_keys = toset([
    "developer",
    "test_operator",
    "production_operator",
  ])

  explicitly_allowed_actions = {
    developer           = []
    test_operator       = var.test_operator_allowed_actions
    production_operator = var.production_operator_allowed_actions
  }

  # These denies remain effective even if an attached AWS managed policy gains
  # broader permissions or additional operational actions are configured.
  sensitive_administration_denies = [
    "account:*",
    "controltower:*",
    "iam:*",
    "identitystore:*",
    "organizations:*",
    "sso:*",
    "budgets:DeleteBudgetAction",
    "budgets:ModifyBudget",
    "cloudtrail:DeleteTrail",
    "cloudtrail:PutEventSelectors",
    "cloudtrail:StopLogging",
    "cloudtrail:UpdateTrail",
    "config:DeleteConfigurationRecorder",
    "config:DeleteDeliveryChannel",
    "config:StopConfigurationRecorder",
    "ec2:DisableEbsEncryptionByDefault",
    "guardduty:DeleteDetector",
    "guardduty:DisassociateFromAdministratorAccount",
    "guardduty:DisassociateMembers",
    "guardduty:StopMonitoringMembers",
    "kms:CreateGrant",
    "kms:DisableKey",
    "kms:PutKeyPolicy",
    "kms:RetireGrant",
    "kms:RevokeGrant",
    "kms:ScheduleKeyDeletion",
    "logs:DeleteLogGroup",
    "logs:DeleteRetentionPolicy",
    "securityhub:DeleteMembers",
    "securityhub:DisableSecurityHub",
    "securityhub:DisassociateFromAdministratorAccount",
    "securityhub:DisassociateMembers",
    "sts:AssumeRole*",
    "sts:SetSourceIdentity",
    "sts:TagSession",
  ]

  allowed_assignment_combinations = toset([
    "viewers:view_only:dev",
    "viewers:view_only:test",
    "viewers:view_only:prod",
    "security_auditors:security_audit:dev",
    "security_auditors:security_audit:test",
    "security_auditors:security_audit:prod",
    "developers:developer:dev",
    "test_operators:test_operator:test",
    "production_operators:production_operator:prod",
  ])
}

resource "aws_identitystore_user" "test" {
  for_each = local.test_users

  identity_store_id = local.identity_store_id
  user_name         = each.value.email
  display_name      = "${each.value.first_name} ${each.value.last_name}"

  name {
    given_name  = each.value.first_name
    family_name = each.value.last_name
  }

  emails {
    value   = each.value.email
    primary = true
    type    = "work"
  }

  lifecycle {
    precondition {
      condition     = var.test_user1_email != var.test_user2_email
      error_message = "test_user1_email and test_user2_email must identify distinct Identity Center users."
    }

    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.management_account_id
      error_message = "Test Identity Center users must be managed from the Organizations management account."
    }
  }
}

resource "aws_identitystore_group" "workload" {
  for_each = local.groups

  identity_store_id = local.identity_store_id
  display_name      = each.value.display_name
  description       = each.value.description

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.management_account_id
      error_message = "Workload Identity Center resources must be managed from the Organizations management account."
    }
  }
}

resource "aws_ssoadmin_permission_set" "workload" {
  for_each = local.permission_sets

  instance_arn     = local.instance_arn
  name             = each.value.name
  description      = each.value.description
  session_duration = each.value.session_duration

  tags = merge(var.common_tags, {
    AssignmentDelegation = "Allowed"
    AccessDomain         = "Workloads"
  })
}

resource "aws_ssoadmin_managed_policy_attachment" "workload" {
  for_each = local.permission_sets

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.key].arn
  managed_policy_arn = each.value.managed_policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "elevated_boundary" {
  for_each = local.elevated_permission_set_keys

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.key].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.explicitly_allowed_actions[each.key]) > 0 ? [
        {
          Sid      = "ExplicitOperationalActions"
          Effect   = "Allow"
          Action   = local.explicitly_allowed_actions[each.key]
          Resource = "*"
        }
      ] : [],
      [
        {
          Sid      = "DenySensitiveAdministration"
          Effect   = "Deny"
          Action   = local.sensitive_administration_denies
          Resource = "*"
        }
      ]
    )
  })
}

resource "aws_ssoadmin_account_assignment" "workload" {
  for_each = var.account_assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.value.permission_set_key].arn
  principal_id       = aws_identitystore_group.workload[each.value.group_key].group_id
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"

  lifecycle {
    precondition {
      condition = contains(
        local.allowed_assignment_combinations,
        "${each.value.group_key}:${each.value.permission_set_key}:${each.value.environment}"
      )
      error_message = "The requested group, permission set, and environment assignment is not in the approved workload access matrix."
    }

    precondition {
      condition     = each.value.account_id != var.management_account_id
      error_message = "Workload permission sets must not be assigned to the Organizations management account."
    }
  }
}
