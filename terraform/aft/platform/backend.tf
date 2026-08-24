# AFT deployment state is deliberately separated from bootstrap state.
# Supply bucket and region during terraform init, for example with -backend-config.
terraform {
  backend "s3" {
    key          = "aft/platform/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
