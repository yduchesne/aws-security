locals {
  evidence_bucket_name = "aws-security-lab-evidence-${var.management_account_id}"
  trail_name           = "aws-security-lab-s3-data-events"
  trail_arn            = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.home_region}:${var.management_account_id}:trail/${local.trail_name}"
  organization_id      = data.aws_organizations_organization.current.id
  lab_accounts         = tomap({ dev = var.lab_account_ids.dev, test = var.lab_account_ids.test })
  sso_role_path_prefix = var.home_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.home_region}/"
}

resource "aws_s3_bucket" "evidence" {
  provider = aws.log_archive

  # checkov:skip=CKV_AWS_18: This is itself a CloudTrail evidence destination; server access logging to another bucket would add a second logging system and recursive operational scope.
  # checkov:skip=CKV_AWS_144: Cross-Region replication is not required for the destructible lab evidence store and would leave additional cross-Region resources after the lab root is destroyed.
  # checkov:skip=CKV2_AWS_62: Event notifications are not required; evidence is consumed through controlled S3 reads after CloudTrail delivery.
  # checkov:skip=CKV_AWS_145: SSE-S3 avoids granting lab readers cross-account KMS decrypt access; the bucket contains scoped lab data-event logs and blocks public access.
  bucket        = local.evidence_bucket_name
  force_destroy = true

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.management.account_id == var.management_account_id
      error_message = "The management provider must authenticate to the configured Organizations management account."
    }

    precondition {
      condition     = data.aws_caller_identity.log_archive.account_id == var.log_archive_account_id
      error_message = "The log_archive provider must assume into the configured Control Tower Log Archive account."
    }

    precondition {
      condition     = !startswith(local.evidence_bucket_name, var.lab_bucket_name_prefix)
      error_message = "The evidence bucket must not use the mutable lab exercise bucket prefix."
    }

    precondition {
      condition = (
        var.log_archive_account_id != var.management_account_id &&
        !contains(values(var.lab_account_ids), var.log_archive_account_id) &&
        !contains(values(var.lab_account_ids), var.management_account_id)
      )
      error_message = "Management, Log Archive, Dev Lab, and Test Lab must be distinct AWS accounts."
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id

  depends_on = [aws_s3_bucket_versioning.evidence]

  rule {
    id     = "expire-lab-evidence"
    status = "Enabled"

    filter {}

    expiration {
      days = var.evidence_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.evidence_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "evidence_bucket" {
  provider = aws.log_archive

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.evidence.arn,
      "${aws_s3_bucket.evidence.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.evidence.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # CreateTrail validates the management-account delivery prefix even for an
  # organization trail. Runtime member-account logs use the organization
  # prefix authorized by the following statement.
  statement {
    sid       = "AllowCloudTrailManagementAccountDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.evidence.arn}/AWSLogs/${var.management_account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "AllowCloudTrailOrganizationDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.evidence.arn}/AWSLogs/${local.organization_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  dynamic "statement" {
    for_each = local.lab_accounts

    content {
      sid       = "Allow${title(statement.key)}LabEvidenceBucketMetadata"
      effect    = "Allow"
      actions   = ["s3:GetBucketLocation"]
      resources = [aws_s3_bucket.evidence.arn]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:root"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:role${local.sso_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.lab_accounts

    content {
      sid       = "Allow${title(statement.key)}LabEvidenceList"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.evidence.arn]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:root"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:role${local.sso_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"]
      }

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values = [
          "AWSLogs/${local.organization_id}/${statement.value}",
          "AWSLogs/${local.organization_id}/${statement.value}/*",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = local.lab_accounts

    content {
      sid    = "Allow${title(statement.key)}LabEvidenceRead"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
      ]
      resources = ["${aws_s3_bucket.evidence.arn}/AWSLogs/${local.organization_id}/${statement.value}/*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:root"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:role${local.sso_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.lab_accounts

    content {
      sid    = "Deny${title(statement.key)}LabEvidenceMutation"
      effect = "Deny"
      not_actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
      ]
      resources = [
        aws_s3_bucket.evidence.arn,
        "${aws_s3_bucket.evidence.arn}/*",
      ]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:root"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${statement.value}:role${local.sso_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "evidence" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.evidence.id
  policy   = data.aws_iam_policy_document.evidence_bucket.json

  depends_on = [
    aws_s3_bucket_ownership_controls.evidence,
    aws_s3_bucket_public_access_block.evidence,
  ]
}

resource "aws_cloudtrail" "lab_s3_data_events" {
  # checkov:skip=CKV_AWS_35: SSE-S3 is intentional so temporary cross-account lab readers need no KMS decrypt grant; scope and retention limit the evidence exposure.
  # checkov:skip=CKV_AWS_252: SNS delivery notifications are unnecessary for this low-volume lab trail; operators verify S3 delivery directly before relying on evidence.
  # checkov:skip=CKV2_AWS_10: This trail is intentionally S3-only to avoid CloudWatch ingestion and storage cost; the Control Tower trail separately handles management-event delivery.
  provider = aws.management

  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.evidence.id
  # AWS requires this setting for every multi-Region trail. The advanced event
  # selector still limits recorded events to S3 object data events, so enabling
  # it does not add global-service management events to this trail.
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  advanced_event_selector {
    name = "LabS3ObjectDataEvents"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:${data.aws_partition.current.partition}:s3:::${var.lab_bucket_name_prefix}"]
    }
  }

  depends_on = [aws_s3_bucket_policy.evidence]
}
