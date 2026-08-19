locals {
  landing_zone_manifest = {
    governedRegions = var.governed_regions

    accessManagement = {
      enabled = true
    }

    backup = {
      enabled = false
    }

    centralizedLogging = {
      enabled   = true
      accountId = aws_organizations_account.log_archive.id

      configurations = {
        loggingBucket = {
          retentionDays = var.log_retention_days
        }

        accessLoggingBucket = {
          retentionDays = var.access_log_retention_days
        }
      }
    }

    config = {
      enabled   = true
      accountId = aws_organizations_account.security_tooling.id
    }

    securityRoles = {
      enabled   = true
      accountId = aws_organizations_account.security_tooling.id
    }
  }
}

# Note: Preventing landing zone creation until all Terraform-owned role permissions are attached.
resource "aws_controltower_landing_zone" "main" {
  version       = var.control_tower_version
  manifest_json = jsonencode(local.landing_zone_manifest)

  # Explicitly depend on policy attachments rather than only IAM roles.
  # Control Tower must not start landing-zone creation until all prerequisite
  # roles have their required permissions.
  depends_on = [
    # AWSControlTowerAdmin
    aws_iam_role_policy_attachment.control_tower_admin_service_role_policy,
    aws_iam_role_policy_attachment.control_tower_identity_center_management,
    aws_iam_role_policy.control_tower_admin,

    # AWSControlTowerCloudTrailRole
    aws_iam_role_policy_attachment.control_tower_cloudtrail,

    # AWSControlTowerStackSetRole
    aws_iam_role_policy.control_tower_stackset,
  ]
}
