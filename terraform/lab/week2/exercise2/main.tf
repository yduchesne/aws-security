# Curriculum: Core
locals {
  role_path                        = "/week2/exercise2/"
  source_boundary_arn              = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  target_boundary_arn              = "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  target_role_arn                  = "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role${local.role_path}${var.target_role_name}"
  target_trusted_principal         = var.trust_mode == "account" ? "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:root" : aws_iam_role.approved.arn
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
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

resource "aws_iam_role" "approved" {
  provider             = aws.source
  name                 = var.approved_role_name
  path                 = local.role_path
  description          = "Approved source role for the Week 2 trust-policy hardening exercise."
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role" "unapproved" {
  provider             = aws.source
  name                 = var.unapproved_role_name
  path                 = local.role_path
  description          = "Second source role used to demonstrate account-level delegation."
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "assume_target" {
  provider = aws.source

  statement {
    sid       = "AssumeOnlyHardeningTarget"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.target_role_arn]
  }
}

resource "aws_iam_role_policy" "approved_assume_target" {
  provider = aws.source
  name     = "AssumeTrustHardeningTarget"
  role     = aws_iam_role.approved.id
  policy   = data.aws_iam_policy_document.assume_target.json
}

# Deliberately identical to the approved role. This isolates the trust-policy
# change: both callers have source-side permission to request the target role.
resource "aws_iam_role_policy" "unapproved_assume_target" {
  provider = aws.source
  name     = "AttemptTrustHardeningTarget"
  role     = aws_iam_role.unapproved.id
  policy   = data.aws_iam_policy_document.assume_target.json
}

data "aws_iam_policy_document" "target_trust" {
  provider = aws.target

  statement {
    sid     = "TrustConfiguredSourcePrincipal"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.target_trusted_principal]
    }
  }
}

resource "aws_iam_role" "target" {
  provider             = aws.target
  name                 = var.target_role_name
  path                 = local.role_path
  description          = "Target role whose trust is first account-wide, then role-specific."
  assume_role_policy   = data.aws_iam_policy_document.target_trust.json
  permissions_boundary = data.aws_iam_policy.target_boundary.arn
  max_session_duration = 3600
}

check "accounts_are_distinct" {
  assert {
    condition     = var.source_account_id != var.target_account_id
    error_message = "source_account_id and target_account_id must be different accounts."
  }
}

check "provider_accounts_match_inputs" {
  assert {
    condition     = data.aws_caller_identity.source.account_id == var.source_account_id
    error_message = "The source provider authenticated to an unexpected account."
  }

  assert {
    condition     = data.aws_caller_identity.target.account_id == var.target_account_id
    error_message = "The target provider authenticated to an unexpected account."
  }
}
