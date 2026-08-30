provider "aws" {
  alias               = "source"
  region              = var.aws_region
  profile             = var.source_aws_profile
  allowed_account_ids = [var.source_account_id]

  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias               = "target"
  region              = var.aws_region
  profile             = var.target_aws_profile
  allowed_account_ids = [var.target_account_id]

  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias               = "management"
  region              = var.aws_region
  profile             = var.management_aws_profile
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = var.common_tags
  }
}

data "aws_caller_identity" "source" {
  provider = aws.source
}

data "aws_caller_identity" "target" {
  provider = aws.target
}

data "aws_caller_identity" "management" {
  provider = aws.management
}

data "aws_partition" "current" {
  provider = aws.source
}

data "aws_organizations_organization" "current" {
  provider = aws.management
}
