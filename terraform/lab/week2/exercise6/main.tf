# Curriculum: Core
locals {
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  bucket_name  = "${var.lab_bucket_name_prefix}exercise6-${var.source_account_id}"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_s3_bucket" "exercise" {
  # checkov:skip=CKV_AWS_18: This short-lived ABAC fixture contains only nonsensitive test strings; organization CloudTrail provides API evidence, and dedicated S3 access-log storage is outside the exercise scope.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is disproportionate for a disposable single-account ABAC fixture and would add persistent cross-Region resources outside this exercise state.
  # checkov:skip=CKV2_AWS_62: Event notifications are unrelated to the tag-authorization control under test; CloudTrail evidence is used instead.
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

resource "aws_s3_object" "alpha" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise6/alpha.txt"
  content = "Project Alpha test object."

  tags = {
    Project = "Alpha"
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_s3_object" "beta" {
  bucket  = aws_s3_bucket.exercise.id
  key     = "exercise6/beta.txt"
  content = "Project Beta test object."

  tags = {
    Project = "Beta"
  }

  depends_on = [aws_s3_bucket_versioning.exercise]
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise6Role"
  path                 = "/week2/exercise6/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn

  tags = {
    Project = "Alpha"
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.source_operator_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise6ProjectAbacPolicy"

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
        Sid      = "ReadObjectsForMatchingProject"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.exercise.arn}/*"
        Condition = {
          StringEquals = {
            "s3:ExistingObjectTag/Project" = "$${aws:PrincipalTag/Project}"
          }
        }
      },
    ]
  })
}

output "role_arn" {
  value = aws_iam_role.exercise.arn
}

output "alpha_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.alpha.key}"
}

output "beta_object_uri" {
  value = "s3://${aws_s3_bucket.exercise.id}/${aws_s3_object.beta.key}"
}
