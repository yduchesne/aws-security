# Curriculum: Core
locals {
  role_path = "/week2/exercise15/"

  source_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  target_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"

  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"

  target_role_arns = [
    "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role${local.role_path}Ex15TargetRole",
    "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role${local.role_path}Ex15ExternalIdTargetRole",
    "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role${local.role_path}Ex15ConditionTargetRole",
  ]

  expected_condition_role_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.role_path}ExpectedConditionRole*"
}

data "aws_iam_policy" "source_boundary" {
  provider = aws.source
  arn      = local.source_boundary_arn
}

data "aws_iam_policy" "target_boundary" {
  provider = aws.target
  arn      = local.target_boundary_arn
}

data "aws_iam_policy_document" "operator_trust" {
  provider = aws.source

  statement {
    sid     = "AllowSpecificLabOperator"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.source_operator_role_arn_pattern]
    }
  }
}

data "aws_iam_policy_document" "caller_assume_targets" {
  provider = aws.source

  statement {
    sid       = "AssumeOnlyExercise15Targets"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = local.target_role_arns
  }

  statement {
    sid       = "ReadCurrentIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "caller_identity_only" {
  provider = aws.source

  statement {
    sid       = "ReadCurrentIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "caller" {
  provider             = aws.source
  name                 = "Ex15CallerRole"
  path                 = local.role_path
  description          = "Working-path source role for the Week 2 Exercise 15 cross-account AssumeRole test."
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_boundary.arn
  max_session_duration = 3600

  tags = merge(var.common_tags, { Name = "Ex15CallerRole", Exercise = "15" })
}

resource "aws_iam_role" "caller_without_assume" {
  provider             = aws.source
  name                 = "Ex15CallerWithoutAssumeRole"
  path                 = local.role_path
  description          = "Failure A source role without an sts:AssumeRole identity Allow."
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_boundary.arn
  max_session_duration = 3600

  tags = merge(var.common_tags, { Name = "Ex15CallerWithoutAssumeRole", Exercise = "15" })
}

resource "aws_iam_role" "untrusted_caller" {
  provider             = aws.source
  name                 = "Ex15UntrustedCallerRole"
  path                 = local.role_path
  description          = "Failure B source role deliberately absent from target trust policies."
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_boundary.arn
  max_session_duration = 3600

  tags = merge(var.common_tags, { Name = "Ex15UntrustedCallerRole", Exercise = "15" })
}

resource "aws_iam_role_policy" "caller" {
  provider = aws.source
  name     = "Exercise15AssumeTargets"
  role     = aws_iam_role.caller.id
  policy   = data.aws_iam_policy_document.caller_assume_targets.json
}

resource "aws_iam_role_policy" "caller_without_assume" {
  provider = aws.source
  name     = "Exercise15Policy"
  role     = aws_iam_role.caller_without_assume.id
  policy   = data.aws_iam_policy_document.caller_identity_only.json
}

resource "aws_iam_role_policy" "untrusted_caller" {
  provider = aws.source
  name     = "Exercise15AssumeTargets"
  role     = aws_iam_role.untrusted_caller.id
  policy   = data.aws_iam_policy_document.caller_assume_targets.json
}

data "aws_iam_policy_document" "target_trust" {
  provider = aws.target

  statement {
    sid     = "TrustOnlyApprovedSourceRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.caller.arn]
    }
  }
}

data "aws_iam_policy_document" "external_id_trust" {
  provider = aws.target

  statement {
    sid     = "TrustApprovedSourceRoleWithExternalId"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.caller.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

data "aws_iam_policy_document" "condition_trust" {
  provider = aws.target

  statement {
    sid     = "TrustRoleWithMismatchedCondition"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.caller.arn]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.expected_condition_role_pattern]
    }
  }
}

resource "aws_iam_role" "target" {
  provider             = aws.target
  name                 = "Ex15TargetRole"
  path                 = local.role_path
  description          = "Working-path target role for the Exercise 15 AssumeRole test."
  assume_role_policy   = data.aws_iam_policy_document.target_trust.json
  permissions_boundary = data.aws_iam_policy.target_boundary.arn
  max_session_duration = 3600
  tags                 = merge(var.common_tags, { Name = "Ex15TargetRole", Exercise = "15" })
}

resource "aws_iam_role" "target_external_id" {
  provider             = aws.target
  name                 = "Ex15ExternalIdTargetRole"
  path                 = local.role_path
  description          = "Failure D target role requiring the configured ExternalId."
  assume_role_policy   = data.aws_iam_policy_document.external_id_trust.json
  permissions_boundary = data.aws_iam_policy.target_boundary.arn
  max_session_duration = 3600
  tags                 = merge(var.common_tags, { Name = "Ex15ExternalIdTargetRole", Exercise = "15" })
}

resource "aws_iam_role" "target_condition" {
  provider             = aws.target
  name                 = "Ex15ConditionTargetRole"
  path                 = local.role_path
  description          = "Failure E target role with an intentionally mismatched PrincipalArn condition."
  assume_role_policy   = data.aws_iam_policy_document.condition_trust.json
  permissions_boundary = data.aws_iam_policy.target_boundary.arn
  max_session_duration = 3600
  tags                 = merge(var.common_tags, { Name = "Ex15ConditionTargetRole", Exercise = "15" })
}

data "aws_iam_policy_document" "target_probe" {
  provider = aws.target

  statement {
    sid       = "ReadCurrentIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "target" {
  provider = aws.target
  name     = "Exercise15TargetProbe"
  role     = aws_iam_role.target.id
  policy   = data.aws_iam_policy_document.target_probe.json
}

resource "aws_iam_role_policy" "target_external_id" {
  provider = aws.target
  name     = "Exercise15TargetProbe"
  role     = aws_iam_role.target_external_id.id
  policy   = data.aws_iam_policy_document.target_probe.json
}

resource "aws_iam_role_policy" "target_condition" {
  provider = aws.target
  name     = "Exercise15TargetProbe"
  role     = aws_iam_role.target_condition.id
  policy   = data.aws_iam_policy_document.target_probe.json
}

resource "aws_organizations_policy" "exercise_scp_deny" {
  count    = var.scp_deny_enabled ? 1 : 0
  provider = aws.management

  name        = "Week2Exercise15DenyAssumeRole"
  description = "Week 2 Exercise 15 disposable fixture: SCP deny blocking cross-account sts:AssumeRole. Safe to delete."
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ExplicitDenyExercise15TargetAssumeRole"
      Effect   = "Deny"
      Action   = ["sts:AssumeRole"]
      Resource = local.target_role_arns
    }]
  })

  tags = merge(var.common_tags, { Name = "Week2Exercise15DenyAssumeRole", Exercise = "15" })
}

resource "aws_organizations_policy_attachment" "exercise" {
  count    = var.scp_deny_enabled ? 1 : 0
  provider = aws.management

  policy_id = aws_organizations_policy.exercise_scp_deny[0].id
  target_id = var.source_account_id
}

check "provider_accounts_match_inputs" {
  assert {
    condition     = data.aws_caller_identity.source.account_id == var.source_account_id
    error_message = "The source provider authenticated to an account other than source_account_id."
  }

  assert {
    condition     = data.aws_caller_identity.target.account_id == var.target_account_id
    error_message = "The target provider authenticated to an account other than target_account_id."
  }
}

check "management_provider_matches_management_account" {
  assert {
    condition = (
      data.aws_caller_identity.management.account_id == var.management_account_id &&
      data.aws_organizations_organization.current.master_account_id == var.management_account_id
    )
    error_message = "The management provider must authenticate to the configured Organizations management account."
  }
}

check "exercise_accounts_are_distinct" {
  assert {
    condition = (
      var.source_account_id != var.target_account_id &&
      var.source_account_id != var.management_account_id &&
      var.target_account_id != var.management_account_id
    )
    error_message = "Source, target, and management account IDs must all be distinct."
  }
}

check "all_fixtures_have_baseline_boundary" {
  assert {
    condition = alltrue([
      aws_iam_role.caller.permissions_boundary == data.aws_iam_policy.source_boundary.arn,
      aws_iam_role.caller_without_assume.permissions_boundary == data.aws_iam_policy.source_boundary.arn,
      aws_iam_role.untrusted_caller.permissions_boundary == data.aws_iam_policy.source_boundary.arn,
      aws_iam_role.target.permissions_boundary == data.aws_iam_policy.target_boundary.arn,
      aws_iam_role.target_external_id.permissions_boundary == data.aws_iam_policy.target_boundary.arn,
      aws_iam_role.target_condition.permissions_boundary == data.aws_iam_policy.target_boundary.arn,
    ])
    error_message = "Every Exercise 15 fixture role must use the pre-provisioned account-local boundary."
  }
}

check "caller_assume_targets_within_boundary_ceiling" {
  assert {
    condition = alltrue([
      for arn in local.target_role_arns : startswith(arn, "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role/week2/")
    ])
    error_message = "Every caller AssumeRole target must remain within the target account's /week2/ role boundary ceiling."
  }
}

check "scp_attachment_targets_only_source_account" {
  assert {
    condition     = !var.scp_deny_enabled || aws_organizations_policy_attachment.exercise[0].target_id == var.source_account_id
    error_message = "The exercise SCP must attach directly to source_account_id only."
  }
}

check "external_id_is_non_empty" {
  assert {
    condition     = length(trimspace(var.external_id)) > 0
    error_message = "external_id must be non-empty."
  }
}
