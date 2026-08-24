resource "aws_servicecatalog_provisioned_product" "aft_management" {
  name                     = var.provisioned_product_name
  product_id               = var.account_factory_product_id
  provisioning_artifact_id = var.account_factory_provisioning_artifact_id
  path_id                  = var.account_factory_path_id

  # Retain the AWS account if this provisioned product is removed from state.
  retain_physical_resources = true

  provisioning_parameters {
    key   = "AccountName"
    value = var.aft_management_account_name
  }

  provisioning_parameters {
    key   = "AccountEmail"
    value = var.aft_management_account_email
  }

  provisioning_parameters {
    key   = "ManagedOrganizationalUnit"
    value = "${var.aft_ou_name} (${var.aft_ou_id})"
  }

  provisioning_parameters {
    key   = "SSOUserEmail"
    value = var.sso_aft_user_email
  }

  provisioning_parameters {
    key   = "SSOUserFirstName"
    value = var.sso_aft_user_first_name
  }

  provisioning_parameters {
    key   = "SSOUserLastName"
    value = var.sso_aft_user_last_name
  }

  lifecycle {
    precondition {
      condition     = var.aft_ou_id != "" && var.aft_control_tower_baseline_arn != ""
      error_message = "The AFT OU and its Control Tower baseline must exist before provisioning the AFT account."
    }
  }

  timeouts {
    create = "120m"
    read   = "20m"
    update = "120m"
    delete = "20m"
  }
}
