# Curriculum: Optional
locals {
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  exercise_policy_actions = [
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
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise12Role"
  path                 = "/week2/exercise12/"
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
    Name     = "Week2Exercise12Role"
    Exercise = "12"
  })
}

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise12Policy"
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
        Sid    = "IntentionallyOvergrantedLabBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.lab_bucket_name_prefix}*",
          "arn:${data.aws_partition.current.partition}:s3:::${var.lab_bucket_name_prefix}*/*",
        ]
      },
    ]
  })
}

resource "aws_accessanalyzer_analyzer" "exercise" {
  analyzer_name = "Week2Exercise12Analyzer"
  type          = "ACCOUNT_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age
    }
  }

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise12Analyzer"
    Exercise = "12"
  })
}

check "provider_account_matches_source" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.source_account_id
    error_message = "The provider authenticated to an account other than source_account_id."
  }
}

check "analyzer_is_unused_access_type" {
  assert {
    condition     = aws_accessanalyzer_analyzer.exercise.type == "ACCOUNT_UNUSED_ACCESS"
    error_message = "The exercise analyzer must remain an account unused-access analyzer."
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

check "bucket_prefix_is_authorized" {
  assert {
    condition     = startswith(var.lab_bucket_name_prefix, "aws-security-week2-")
    error_message = "lab_bucket_name_prefix must use the boundary-authorized Week 2 prefix."
  }
}
