# Identity Center administration is isolated from landing-zone state.
terraform {
  backend "s3" {
    key          = "identity-center/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
