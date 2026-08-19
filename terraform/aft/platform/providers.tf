provider "aws" {
  region = var.home_region

  # Fail provider configuration before Terraform can plan or apply resources
  # when the active credentials belong to any other AWS account.
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = var.common_tags
  }
}
