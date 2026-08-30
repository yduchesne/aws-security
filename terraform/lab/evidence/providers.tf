provider "aws" {
  alias               = "management"
  region              = var.home_region
  profile             = var.management_aws_profile
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias               = "log_archive"
  region              = var.home_region
  profile             = var.management_aws_profile
  allowed_account_ids = [var.log_archive_account_id]

  assume_role {
    role_arn     = "arn:${data.aws_partition.current.partition}:iam::${var.log_archive_account_id}:role/${var.log_archive_execution_role_name}"
    session_name = "LabEvidenceTerraform"
  }

  default_tags {
    tags = var.common_tags
  }
}

data "aws_partition" "current" {
  provider = aws.management
}

data "aws_caller_identity" "management" {
  provider = aws.management
}

data "aws_caller_identity" "log_archive" {
  provider = aws.log_archive
}

data "aws_organizations_organization" "current" {
  provider = aws.management
}
