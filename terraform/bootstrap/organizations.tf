# Control Tower requires AWS Organizations with all features enabled.
# AWS's own API walkthrough uses: CreateOrganization --feature-set ALL
resource "aws_organizations_organization" "main" {
  feature_set = "ALL"

  # Control Tower requires service control policies. Declare this invariant so
  # Terraform does not attempt to disable SCP support on the organization root.
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]

  # Control Tower and delegated AWS services manage trusted service access.
  # This root must not remove integrations that it does not own.
  lifecycle {
    ignore_changes = [
      aws_service_access_principals,
    ]
  }
}

resource "aws_organizations_organizational_unit" "security" {
  name      = var.security_ou_name
  parent_id = aws_organizations_organization.main.roots[0].id
}
