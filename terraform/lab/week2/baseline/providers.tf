provider "aws" {
  alias               = "source"
  region              = var.aws_region
  profile             = var.lab_baseline_aws_profiles.dev
  allowed_account_ids = [var.lab_account_ids.dev]

  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias               = "target"
  region              = var.aws_region
  profile             = var.lab_baseline_aws_profiles.test
  allowed_account_ids = [var.lab_account_ids.test]

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

data "aws_partition" "current" {
  provider = aws.source
}
