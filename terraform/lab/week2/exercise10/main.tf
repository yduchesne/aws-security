# Curriculum: Optional
locals {
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise10Role"
  path                 = "/week2/exercise10/"
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
    Name     = "Week2Exercise10Role"
    Exercise = "10"
  })
}

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise10Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" }]
  })
}

resource "aws_accessanalyzer_analyzer" "exercise" {
  analyzer_name = "Week2Exercise10Analyzer"
  type          = "ACCOUNT"

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise10Analyzer"
    Exercise = "10"
  })
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: Disposable non-sensitive authorization-test data; centralized CloudTrail captures the exercise evidence and a dedicated access-log bucket would expand this exercise's scope.
  # checkov:skip=CKV2_AWS_62: Event-driven processing is outside this detection exercise; IAM Access Analyzer and CloudTrail are the required evidence sources.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for short-lived generated lab data and would add another account/Region trust boundary.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects disposable non-sensitive objects without introducing KMS permissions that would obscure the policy-analysis lesson.
  bucket        = var.bucket_name
  force_destroy = true

  tags = merge(var.common_tags, {
    Name     = var.bucket_name
    Exercise = "10"
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

resource "aws_s3_object" "exercise" {
  bucket                 = aws_s3_bucket.exercise.id
  key                    = "exercise-10/fixture.txt"
  content                = "Week 2 Exercise 10 Access Analyzer fixture.\n"
  server_side_encryption = "AES256"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.exercise]
}

# This grant is intentionally outside the analyzer account's zone of trust.
# A cross-account principal is not a public principal, so S3's
# block_public_policy setting does not prevent this exercise policy.
data "aws_iam_policy_document" "external_grant" {
  count = var.external_grant_enabled ? 1 : 0

  statement {
    sid    = "IntentionalExternalAccountRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.external_account_id}:root"]
    }

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      aws_s3_bucket.exercise.arn,
      "${aws_s3_bucket.exercise.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "external_grant" {
  count = var.external_grant_enabled ? 1 : 0

  bucket = aws_s3_bucket.exercise.id
  policy = data.aws_iam_policy_document.external_grant[0].json

  depends_on = [aws_s3_bucket_public_access_block.exercise]
}

check "external_account_is_outside_zone_of_trust" {
  assert {
    condition     = var.external_account_id != var.source_account_id
    error_message = "external_account_id must differ from source_account_id so the policy is cross-account."
  }
}

check "bucket_name_is_authorized" {
  assert {
    condition     = startswith(var.bucket_name, var.lab_bucket_name_prefix)
    error_message = "bucket_name must begin with lab_bucket_name_prefix authorized by the lab boundary."
  }
}

check "provider_account_matches_source" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.source_account_id
    error_message = "The provider authenticated to an account other than source_account_id."
  }
}
