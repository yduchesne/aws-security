locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.current.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]
}

# Account Factory created or referenced this user. Looking it up by UserName
# avoids creating a duplicate identity or taking ownership from Control Tower.
data "aws_identitystore_user" "aft_account_owner" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.sso_aft_user_email
    }
  }
}

resource "aws_identitystore_group" "aft_platform_administrators" {
  identity_store_id = local.identity_store_id
  display_name      = "AFTPlatformAdministrators"
  description       = "Named human administrators who inspect, authorize source connections, and operate the AFT platform in the dedicated AFT management account."
}

resource "aws_identitystore_group_membership" "aft_account_owner" {
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.aft_platform_administrators.group_id
  member_id         = data.aws_identitystore_user.aft_account_owner.user_id
}

resource "aws_ssoadmin_permission_set" "aft_platform_administration" {
  instance_arn     = local.instance_arn
  name             = "AFTPlatformAdministration"
  description      = "Read AFT resources, authorize CodeConnections, and perform limited AFT pipeline operations in the AFT management account."
  session_duration = var.privileged_session_duration
  tags = merge(var.common_tags, {
    SecurityBoundary = "Protected"
  })
}

# Read access supports AFT troubleshooting without granting general write
# administration in the AFT management account.
resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.aft_platform_administration.arn
  managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssoadmin_permission_set_inline_policy" "aft_platform_administration" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.aft_platform_administration.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InspectAndUpdateAFTCodeConnections"
        Effect = "Allow"
        Action = [
          "codeconnections:GetConnection",
          "codeconnections:ListConnections",
          "codeconnections:UpdateConnectionInstallation",
          "codestar-connections:GetConnection",
          "codestar-connections:ListConnections",
          "codestar-connections:UpdateConnectionInstallation"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:codeconnections:${var.home_region}:${var.aft_management_account_id}:connection/*"
      },
      {
        Sid    = "AuthorizeGitHubOAuthHandshake"
        Effect = "Allow"
        Action = [
          "codeconnections:GetIndividualAccessToken",
          "codeconnections:GetInstallationUrl",
          "codeconnections:StartOAuthHandshake"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "codeconnections:ProviderType" = "GitHub"
          }
        }
      },
      {
        Sid      = "ListGitHubInstallationTargets"
        Effect   = "Allow"
        Action   = "codeconnections:ListInstallationTargets"
        Resource = "*"
      },
      {
        Sid    = "OperateAFTPipelines"
        Effect = "Allow"
        Action = [
          "codepipeline:RetryStageExecution",
          "codepipeline:StartPipelineExecution",
          "codepipeline:StopPipelineExecution"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:codepipeline:*:${var.aft_management_account_id}:*"
      },
      {
        Sid    = "DenyIdentityAndOrganizationAdministration"
        Effect = "Deny"
        Action = [
          "identitystore:Create*",
          "identitystore:Delete*",
          "identitystore:Update*",
          "organizations:Create*",
          "organizations:Delete*",
          "organizations:Deregister*",
          "organizations:Disable*",
          "organizations:Enable*",
          "organizations:Invite*",
          "organizations:LeaveOrganization",
          "organizations:MoveAccount",
          "organizations:Register*",
          "organizations:Remove*",
          "organizations:Update*",
          "sso:Attach*",
          "sso:Create*",
          "sso:Delete*",
          "sso:Detach*",
          "sso:ProvisionPermissionSet",
          "sso:Put*",
          "sso:TagResource",
          "sso:UntagResource",
          "sso:Update*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyIAMMutation"
        Effect = "Deny"
        Action = [
          "iam:Add*",
          "iam:Attach*",
          "iam:ChangePassword",
          "iam:Create*",
          "iam:DeactivateMFADevice",
          "iam:Delete*",
          "iam:Detach*",
          "iam:EnableMFADevice",
          "iam:PassRole",
          "iam:Put*",
          "iam:Remove*",
          "iam:ResetServiceSpecificCredential",
          "iam:ResyncMFADevice",
          "iam:SetDefaultPolicyVersion",
          "iam:SetSecurityTokenServicePreferences",
          "iam:Tag*",
          "iam:Untag*",
          "iam:Update*",
          "iam:Upload*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssoadmin_account_assignment" "aft_platform_administrators" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.aft_platform_administration.arn
  principal_id       = aws_identitystore_group.aft_platform_administrators.group_id
  principal_type     = "GROUP"
  target_id          = var.aft_management_account_id
  target_type        = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.read_only,
    aws_ssoadmin_permission_set_inline_policy.aft_platform_administration,
  ]
}
