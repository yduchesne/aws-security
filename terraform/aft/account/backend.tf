# Supply the S3 bucket and Region during terraform init.
terraform {
  backend "s3" {
    key          = "aft/account/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
