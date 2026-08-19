# Using the S3 backend for persisting TF state.
# We're targeting the boostrap S3 bucket.
#
# Note: Terraform backend configuration is initialized before normal
# input variables are evaluated, so var.* references cannot be used
# inside a backend "s3" block
terraform {
  backend "s3" {
    key          = "control-tower/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
