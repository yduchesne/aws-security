# Workload access is isolated from privileged Identity Center administration.
terraform {
  backend "s3" {
    key          = "identity-center/workload-access/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
