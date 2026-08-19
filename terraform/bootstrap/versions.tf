terraform {
  required_version = "~> 1.15"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Permits compatible 6.x updates while preventing an automatic jump to AWS provider 7.x.
      # Setting the version to "6.55.0" would prevent updates.
      version = "~> 6.55"
    }
  }
}
