###############################################################################
# AWS Control Tower Account Factory for Terraform (AFT)
#
# AFT is deployed from the Control Tower management account but installs its
# operational infrastructure into the dedicated AFT management account and the
# Control Tower shared accounts as required.
###############################################################################

module "aft" {
  # AWS AFT release 1.20.1, pinned to the immutable commit behind the tag.
  source = "git::https://github.com/aws-ia/terraform-aws-control_tower_account_factory.git?ref=2ba0f21627e90f86115031bc9f6ea1eb50cd411f"

  ct_management_account_id  = var.management_account_id
  aft_management_account_id = var.aft_management_account_id
  audit_account_id          = var.audit_account_id
  log_archive_account_id    = var.log_archive_account_id
  ct_home_region            = var.home_region

  terraform_distribution = "oss"
  vcs_provider           = var.vcs_provider

  account_request_repo_name                       = var.account_request_repo_name
  account_request_repo_branch                     = var.repository_branch
  global_customizations_repo_name                 = var.global_customizations_repo_name
  global_customizations_repo_branch               = var.repository_branch
  account_customizations_repo_name                = var.account_customizations_repo_name
  account_customizations_repo_branch              = var.repository_branch
  account_provisioning_customizations_repo_name   = var.account_provisioning_customizations_repo_name
  account_provisioning_customizations_repo_branch = var.repository_branch

  # Keep AFT compute outside a customer VPC for this architecture. This avoids
  # the module's NAT gateways and interface endpoints; see docs/aft-setup.md.
  aft_enable_vpc                          = var.aft_enable_vpc
  aft_metrics_reporting                   = var.aft_metrics_reporting
  aft_feature_delete_default_vpcs_enabled = var.aft_feature_delete_default_vpcs_enabled

  tags = var.common_tags
}
