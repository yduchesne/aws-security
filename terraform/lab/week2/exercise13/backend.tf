terraform {
  backend "s3" {
    key          = "lab/week2/exercise13/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
