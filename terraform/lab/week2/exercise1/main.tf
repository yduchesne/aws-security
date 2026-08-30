# Curriculum: Core
locals {
  role_path                        = "/week2/exercise1/"
  source_role_boundary_arn         = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  target_role_boundary_arn         = "arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
}

data "aws_iam_policy" "source_role_boundary" {
  provider = aws.source
  arn      = local.source_role_boundary_arn
}

data "aws_iam_policy" "target_role_boundary" {
  provider = aws.target
  arn      = local.target_role_boundary_arn
}

data "aws_iam_policy_document" "source_operator_trust" {
  provider = aws.source

  statement {
    sid     = "AllowSpecificOperator"
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

resource "aws_iam_role" "caller" {
  provider = aws.source

  name                 = var.caller_role_name
  path                 = local.role_path
  description          = "Approved source role for the Week 2 cross-account AssumeRole exercise."
  assume_role_policy   = data.aws_iam_policy_document.source_operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_role_boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role" "untrusted_caller" {
  provider = aws.source

  name                 = var.untrusted_role_name
  path                 = local.role_path
  description          = "Negative-test role that the target role deliberately does not trust."
  assume_role_policy   = data.aws_iam_policy_document.source_operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_role_boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "assume_target" {
  provider = aws.source

  statement {
    sid       = "AssumeOnlyExerciseTargetRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${var.target_account_id}:role${local.role_path}${var.target_role_name}"]
  }
}

resource "aws_iam_role_policy" "caller_assume_target" {
  provider = aws.source

  name   = "AssumeExerciseTargetRole"
  role   = aws_iam_role.caller.id
  policy = data.aws_iam_policy_document.assume_target.json
}

# This policy intentionally proves that an identity-side Allow is insufficient
# when the target role's trust policy does not trust the calling principal.
resource "aws_iam_role_policy" "untrusted_caller_assume_target" {
  provider = aws.source

  name   = "AttemptExerciseTargetRole"
  role   = aws_iam_role.untrusted_caller.id
  policy = data.aws_iam_policy_document.assume_target.json
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

resource "aws_iam_role" "target_read" {
  provider = aws.target

  name                 = var.target_role_name
  path                 = local.role_path
  description          = "Target-account role with read-only access to the approved exercise resource."
  assume_role_policy   = data.aws_iam_policy_document.target_trust.json
  permissions_boundary = data.aws_iam_policy.target_role_boundary.arn
  max_session_duration = 3600
}

resource "aws_s3_bucket" "approved" {
  # checkov:skip=CKV_AWS_18: Disposable non-sensitive authorization-test data; centralized CloudTrail captures the IAM/STS evidence and a dedicated access-log bucket would expand this exercise's scope.
  # checkov:skip=CKV2_AWS_62: Event-driven processing is outside this authorization exercise; CloudTrail is the required evidence source.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for short-lived generated lab data and would add another account/Region trust boundary.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects disposable non-sensitive objects without introducing KMS permissions that would obscure the IAM policy-evaluation lesson.
  provider = aws.target

  bucket        = var.approved_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket" "unrelated" {
  # checkov:skip=CKV_AWS_18: Disposable non-sensitive authorization-test data; centralized CloudTrail captures the IAM/STS evidence and a dedicated access-log bucket would expand this exercise's scope.
  # checkov:skip=CKV2_AWS_62: Event-driven processing is outside this authorization exercise; CloudTrail is the required evidence source.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for short-lived generated lab data and would add another account/Region trust boundary.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects disposable non-sensitive objects without introducing KMS permissions that would obscure the IAM policy-evaluation lesson.
  provider = aws.target

  bucket        = var.unrelated_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "exercise" {
  for_each = {
    approved  = aws_s3_bucket.approved.id
    unrelated = aws_s3_bucket.unrelated.id
  }
  provider = aws.target

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "exercise" {
  for_each = {
    approved  = aws_s3_bucket.approved.id
    unrelated = aws_s3_bucket.unrelated.id
  }
  provider = aws.target

  bucket = each.value

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exercise" {
  for_each = {
    approved  = aws_s3_bucket.approved.id
    unrelated = aws_s3_bucket.unrelated.id
  }
  provider = aws.target

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "exercise" {
  for_each = {
    approved  = aws_s3_bucket.approved.id
    unrelated = aws_s3_bucket.unrelated.id
  }
  provider = aws.target

  bucket = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "exercise" {
  for_each = {
    approved  = aws_s3_bucket.approved.id
    unrelated = aws_s3_bucket.unrelated.id
  }
  provider = aws.target

  bucket = each.value

  rule {
    id     = "expire-disposable-lab-data"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_s3_object" "approved" {
  provider = aws.target

  bucket                 = aws_s3_bucket.approved.id
  key                    = var.approved_object_key
  content                = "Week 2 Exercise 1 approved cross-account read target.\n"
  server_side_encryption = "AES256"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.exercise]
}

resource "aws_s3_object" "unrelated" {
  provider = aws.target

  bucket                 = aws_s3_bucket.unrelated.id
  key                    = "exercise-1/unrelated.txt"
  content                = "The exercise target role must not read this object.\n"
  server_side_encryption = "AES256"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.exercise]
}

data "aws_iam_policy_document" "target_read" {
  provider = aws.target

  statement {
    sid    = "ReadApprovedBucketMetadata"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.approved.arn]
  }

  statement {
    sid       = "ReadOnlyApprovedObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.approved.arn}/${var.approved_object_key}"]
  }
}

resource "aws_iam_role_policy" "target_read" {
  provider = aws.target

  name   = "ReadOnlyApprovedExerciseResource"
  role   = aws_iam_role.target_read.id
  policy = data.aws_iam_policy_document.target_read.json
}

check "lab_bucket_names_are_authorized" {
  assert {
    condition = (
      startswith(var.approved_bucket_name, var.lab_bucket_name_prefix) &&
      startswith(var.unrelated_bucket_name, var.lab_bucket_name_prefix) &&
      var.approved_bucket_name != var.unrelated_bucket_name
    )
    error_message = "Exercise bucket names must be distinct and begin with lab_bucket_name_prefix."
  }
}

check "exercise_accounts_are_distinct" {
  assert {
    condition     = var.source_account_id != var.target_account_id
    error_message = "source_account_id and target_account_id must identify different AWS accounts."
  }
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
