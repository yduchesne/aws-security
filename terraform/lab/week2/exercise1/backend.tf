terraform {
  backend "s3" {
    key          = "lab/week2/exercise1/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
