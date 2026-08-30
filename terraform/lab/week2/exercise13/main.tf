# Curriculum: Optional
locals {
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  boundary_ceiling_actions = [
    "sts:GetCallerIdentity",
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:ListBucketVersions",
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:DeleteObjectVersion",
  ]
  s3_boundary_actions = [
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:ListBucketVersions",
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:DeleteObjectVersion",
  ]
  exercise_policy_actions = [
    "sts:GetCallerIdentity",
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:GetObject",
    "s3:PutObject",
  ]
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise13Role"
  path                 = "/week2/exercise13/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:PrincipalArn" = local.source_operator_role_arn_pattern
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise13Role"
    Exercise = "13"
  })
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: Disposable non-sensitive authorization-test data; centralized CloudTrail captures the exercise evidence and a dedicated access-log bucket would expand this exercise's scope.
  # checkov:skip=CKV2_AWS_62: Event-driven processing is outside this authorization exercise; CloudTrail is the required evidence source.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for short-lived generated lab data and would add another account/Region trust boundary.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects disposable non-sensitive objects without introducing KMS permissions that would obscure the policy-analysis lesson.
  bucket        = var.bucket_name
  force_destroy = true

  tags = merge(var.common_tags, {
    Name     = var.bucket_name
    Exercise = "13"
  })
}

resource "aws_s3_bucket_public_access_block" "exercise" {
  bucket                  = aws_s3_bucket.exercise.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "exercise" {
  bucket = aws_s3_bucket.exercise.id

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

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise13Policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "IdentityVerification"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Sid    = "AllowExercise13BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = [
          aws_s3_bucket.exercise.arn,
          "${aws_s3_bucket.exercise.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_organizations_policy" "exercise_scp_deny" {
  count    = var.scp_deny_enabled ? 1 : 0
  provider = aws.management

  name        = "Week2Exercise13DenyS3ObjectWrites"
  description = "Week 2 Exercise 13 disposable fixture: explicit SCP deny overriding an identity allow. Safe to delete."
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ExplicitDenyExercise13BucketObjectWrites"
      Effect   = "Deny"
      Action   = var.scp_deny_actions
      Resource = ["${aws_s3_bucket.exercise.arn}/*"]
    }]
  })

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise13DenyS3ObjectWrites"
    Exercise = "13"
  })
}

resource "aws_organizations_policy_attachment" "exercise" {
  count    = var.scp_deny_enabled ? 1 : 0
  provider = aws.management

  policy_id = aws_organizations_policy.exercise_scp_deny[0].id
  target_id = var.source_account_id
}

check "provider_account_matches_source" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.source_account_id
    error_message = "The default provider authenticated to an account other than source_account_id."
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

check "source_account_is_enrolled_member" {
  assert {
    condition = (
      var.source_account_id != var.management_account_id &&
      contains([for account in data.aws_organizations_organization.current.accounts : account.id], var.source_account_id)
    )
    error_message = "source_account_id must be a non-management member account in the organization."
  }
}

check "scp_attachment_targets_only_source_account" {
  assert {
    condition     = !var.scp_deny_enabled || aws_organizations_policy_attachment.exercise[0].target_id == var.source_account_id
    error_message = "The exercise SCP must attach directly to source_account_id only."
  }
}

check "role_has_baseline_boundary" {
  assert {
    condition     = aws_iam_role.exercise.permissions_boundary == data.aws_iam_policy.lab_role_boundary.arn
    error_message = "The exercise role must use the pre-provisioned lab permissions boundary."
  }
}

check "exercise_policy_within_boundary_ceiling" {
  assert {
    condition     = alltrue([for action in local.exercise_policy_actions : contains(local.boundary_ceiling_actions, action)])
    error_message = "Every exercise policy action must remain within the documented boundary ceiling."
  }
}

check "bucket_name_is_authorized" {
  assert {
    condition     = startswith(var.bucket_name, var.lab_bucket_name_prefix)
    error_message = "bucket_name must begin with lab_bucket_name_prefix authorized by the lab boundary."
  }
}

check "scp_deny_actions_within_ceiling" {
  assert {
    condition     = length(var.scp_deny_actions) > 0 && alltrue([for action in var.scp_deny_actions : contains(local.s3_boundary_actions, action)])
    error_message = "scp_deny_actions must be non-empty and limited to the documented Week 2 S3 boundary actions."
  }
}
