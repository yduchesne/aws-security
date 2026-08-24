provider "aws" {
  region              = var.home_region
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = var.common_tags
  }
}
