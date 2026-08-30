terraform {
  backend "s3" {
    key          = "lab/foundation/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
