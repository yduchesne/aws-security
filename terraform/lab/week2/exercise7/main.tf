# Curriculum: Optional
locals {
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  bucket_name                      = "${var.lab_bucket_name_prefix}exercise7-${var.source_account_id}"
  sso_role_path_prefix             = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.sso_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: This short-lived ABAC fixture contains only nonsensitive test strings; organization CloudTrail provides API evidence, and dedicated S3 access-log storage is outside the exercise scope.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for a disposable single-account ABAC fixture and would add persistent cross-Region resources outside this exercise state.
  # checkov:skip=CKV2_AWS_62: Event notifications are unrelated to the tag-authorization control under test; configured CloudTrail data-event evidence is used instead.
  # checkov:skip=CKV2_AWS_61: The bucket is short-lived, versioned, and force-destroyed with the exercise; a lifecycle policy would not improve its intended temporary retention model.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects the nonsensitive fixture objects at rest; the approved lab boundary intentionally grants no KMS data-plane permissions to this role.
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "exercise" {
  bucket = aws_s3_bucket.exercise.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

resource "aws_s3_object" "alpha_development" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise7/alpha-development.txt"
  content = "Project Alpha development test object."

  tags = {
    Project     = "Alpha"
    Environment = "Development"
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_s3_object" "alpha_production" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise7/alpha-production.txt"
  content = "Project Alpha production test object."

  tags = {
    Project     = "Alpha"
    Environment = "Production"
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_s3_object" "beta_development" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise7/beta-development.txt"
  content = "Project Beta development test object."

  tags = {
    Project     = "Beta"
    Environment = "Development"
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise7Role"
  path                 = "/week2/exercise7/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn

  tags = {
    Project     = "Alpha"
    Environment = "Development"
  }

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
}

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise7ProjectEnvironmentAbacPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCurrentIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid      = "ReadObjectsForMatchingProjectAndEnvironment"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.exercise.arn}/*"
        Condition = {
          StringEquals = {
            "s3:ExistingObjectTag/Project"     = "$${aws:PrincipalTag/Project}"
            "s3:ExistingObjectTag/Environment" = "$${aws:PrincipalTag/Environment}"
          }
        }
      },
    ]
  })
}

output "role_arn" {
  value = aws_iam_role.exercise.arn
}

output "bucket_name" {
  value = aws_s3_bucket.exercise.id
}

output "alpha_development_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.alpha_development.key}"
}

output "alpha_production_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.alpha_production.key}"
}

output "beta_development_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.beta_development.key}"
}
