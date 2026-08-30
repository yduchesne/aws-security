provider "aws" {
  alias               = "management"
  region              = var.home_region
  profile             = var.management_aws_profile
  allowed_account_ids = [var.management_account_id]
}

provider "aws" {
  alias               = "dev"
  region              = var.home_region
  profile             = var.management_aws_profile
  allowed_account_ids = [var.lab_account_ids.dev]

  assume_role {
    role_arn     = "arn:${data.aws_partition.current.partition}:iam::${var.lab_account_ids.dev}:role/${var.lab_execution_role_name}"
    session_name = "LabFoundationTerraform"
  }

  default_tags {
    tags = var.common_tags
  }
}

data "aws_partition" "current" {
  provider = aws.management
}

data "aws_caller_identity" "dev" {
  provider = aws.dev
}

data "aws_availability_zones" "available" {
  provider = aws.dev
  state    = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required", "opted-in"]
  }
}
