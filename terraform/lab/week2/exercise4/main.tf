# Curriculum: Optional
locals {
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  bucket_name                      = "${var.lab_bucket_name_prefix}exercise4-${var.source_account_id}"
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: This short-lived boundary fixture contains only a nonsensitive test string; organization CloudTrail provides API evidence, and dedicated S3 access-log storage is outside the exercise scope.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for a disposable single-account boundary fixture and would add persistent cross-Region resources outside this exercise state.
  # checkov:skip=CKV2_AWS_62: Event notifications are unrelated to the permissions-boundary control under test; configured CloudTrail data-event evidence is used instead.
  # checkov:skip=CKV2_AWS_61: The bucket is short-lived, versioned, and force-destroyed with the exercise; a lifecycle policy would not improve its intended temporary retention model.
  # checkov:skip=CKV_AWS_145: SSE-S3 protects the nonsensitive fixture object; the approved lab boundary intentionally grants no KMS data-plane permissions to this role.
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

resource "aws_s3_object" "allowed" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise4/allowed.txt"
  content = "The administrator-like grant is constrained by the role boundary."

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise4Role"
  path                 = "/week2/exercise4/"
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
}

resource "aws_iam_role_policy" "administrator_like" {
  # checkov:skip=CKV_AWS_62: Full administrative syntax is intentional in this isolated exercise so learners can prove that the boundary limits its effective permissions.
  # checkov:skip=CKV_AWS_63: Action "*" is the deliberate test input; the baseline-owned boundary excludes IAM, credential, Organizations, and unrelated data-plane operations.
  # checkov:skip=CKV_AWS_286: Apparent privilege-escalation actions are outside the attached boundary and therefore are not effective permissions.
  # checkov:skip=CKV_AWS_287: Apparent credential-read actions are outside the attached boundary and therefore are not effective permissions.
  # checkov:skip=CKV_AWS_288: Apparent exfiltration actions are outside the attached boundary; effective S3 access is restricted to the approved lab bucket prefix.
  # checkov:skip=CKV2_AWS_40: Full IAM syntax is intentional for boundary evaluation; the attached boundary grants no IAM administration to this role.
  # checkov:skip=CKV_AWS_289: The broad inline grant is the deliberate subject of this boundary experiment; the immutable baseline-owned boundary limits effective permissions to STS identity checks, approved Week 2 role assumption, and named-prefix S3 data access.
  # checkov:skip=CKV_AWS_290: Write access is intentionally broad in the identity policy to demonstrate that the boundary—not this grant—sets the effective ceiling; no IAM, Organizations, or governance action is present in that boundary.
  # checkov:skip=CKV_AWS_355: Resource "*" is intentional for the administrator-like test grant; effective access remains intersected with the narrowly scoped WorkloadLabRoleBoundary documented in the exercise.
  role = aws_iam_role.exercise.id
  name = "Exercise4AdministratorLikePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DeliberatelyBroadAdministratorLikeGrant"
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

output "role_arn" {
  value = aws_iam_role.exercise.arn
}

output "bucket_name" {
  value = aws_s3_bucket.exercise.id
}

output "allowed_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.allowed.key}"
}
