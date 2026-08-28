provider "aws" {
  region              = var.aws_region
  profile             = var.source_aws_profile
  allowed_account_ids = [var.source_account_id]
  default_tags {
    tags = var.common_tags
  }
}
data "aws_caller_identity" "current" {}
