# AFT human-access resources are isolated from both Account Factory and the
# general Identity Center administration state.
terraform {
  backend "s3" {
    key          = "identity-center/aft-access/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
