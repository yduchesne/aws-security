terraform {
  backend "s3" {
    key          = "lab/evidence/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
