locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.current.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]
  instance_id       = element(split("/", local.instance_arn), 1)

  identity_store_arn      = "arn:${data.aws_partition.current.partition}:identitystore::${var.management_account_id}:identitystore/${local.identity_store_id}"
  all_groups_arn          = "arn:${data.aws_partition.current.partition}:identitystore:::group/*"
  all_users_arn           = "arn:${data.aws_partition.current.partition}:identitystore:::user/*"
  all_memberships_arn     = "arn:${data.aws_partition.current.partition}:identitystore:::membership/*"
  permission_set_wildcard = "arn:${data.aws_partition.current.partition}:sso:::permissionSet/${local.instance_id}/*"
  account_wildcard        = "arn:${data.aws_partition.current.partition}:sso:::account/*"
  management_account_arn  = "arn:${data.aws_partition.current.partition}:sso:::account/${var.management_account_id}"

  control_tower_protected_group_names = toset([
    "AWSAccountFactory",
    "AWSAuditAccountAdmins",
    "AWSControlTowerAdmins",
    "AWSLogArchiveAdmins",
    "AWSLogArchiveViewers",
    "AWSSecurityAuditPowerUsers",
    "AWSSecurityAuditors",
    "AWSServiceCatalogAdmins",
  ])

  administrators = {
    identity_store = {
      group_name  = "AWSIdentityStoreAdmins"
      description = "Administers Identity Center users, groups, memberships, and identity lifecycle. Privileged group changes require independent review."
      email       = var.sso_identity_store_admin_email
      first_name  = var.sso_identity_store_admin_first_name
      last_name   = var.sso_identity_store_admin_last_name
    }
    permission_set = {
      group_name  = "AWSPermissionSetAdmins"
      description = "Administers IAM Identity Center permission-set definitions. Account assignments are a separate responsibility."
      email       = var.sso_permission_set_admin_email
      first_name  = var.sso_permission_set_admin_first_name
      last_name   = var.sso_permission_set_admin_last_name
    }
    access_assignment = {
      group_name  = "AWSAccessAssignmentAdmins"
      description = "Administers IAM Identity Center account assignments using existing approved permission sets."
      email       = var.sso_access_assignment_admin_email
      first_name  = var.sso_access_assignment_admin_first_name
      last_name   = var.sso_access_assignment_admin_last_name
    }
  }
}

data "aws_identitystore_group" "control_tower_protected" {
  for_each = local.control_tower_protected_group_names

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

resource "aws_identitystore_group" "administrators" {
  for_each = local.administrators

  identity_store_id = local.identity_store_id
  display_name      = each.value.group_name
  description       = each.value.description
}

resource "aws_identitystore_user" "administrators" {
  for_each = local.administrators

  identity_store_id = local.identity_store_id
  user_name         = each.value.email
  display_name      = "${each.value.first_name} ${each.value.last_name}"

  name {
    given_name  = each.value.first_name
    family_name = each.value.last_name
  }

  emails {
    value   = each.value.email
    primary = true
    type    = "work"
  }

  lifecycle {
    precondition {
      condition = length(distinct([
        var.sso_identity_store_admin_email,
        var.sso_permission_set_admin_email,
        var.sso_access_assignment_admin_email,
      ])) == 3
      error_message = "The three privileged responsibilities require three distinct Identity Center user email addresses."
    }
  }
}

resource "aws_identitystore_group_membership" "administrators" {
  for_each = local.administrators

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.administrators[each.key].group_id
  member_id         = aws_identitystore_user.administrators[each.key].user_id
}

resource "aws_ssoadmin_permission_set" "identity_store_admin" {
  instance_arn     = local.instance_arn
  name             = "IdentityStoreAdministration"
  description      = "Identity lifecycle administration. Privileged group membership requires independent review."
  session_duration = var.privileged_session_duration
  tags = merge(var.common_tags, {
    SecurityBoundary = "Protected"
  })
}

resource "aws_ssoadmin_permission_set" "permission_set_admin" {
  instance_arn     = local.instance_arn
  name             = "PermissionSetAdministration"
  description      = "Permission-set definition administration without account-assignment administration."
  session_duration = var.privileged_session_duration
  tags = merge(var.common_tags, {
    SecurityBoundary = "Protected"
  })
}

resource "aws_ssoadmin_permission_set" "access_assignment_admin" {
  instance_arn     = local.instance_arn
  name             = "AccessAssignmentAdministration"
  description      = "Account-assignment administration without permission-set definition administration."
  session_duration = var.privileged_session_duration
  tags = merge(var.common_tags, {
    SecurityBoundary = "Protected"
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "identity_store_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.identity_store_admin.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IdentityStoreLifecycleAdministration"
        Effect = "Allow"
        Action = [
          "identitystore:CreateGroup",
          "identitystore:CreateGroupMembership",
          "identitystore:CreateUser",
          "identitystore:DeleteGroup",
          "identitystore:DeleteGroupMembership",
          "identitystore:DeleteUser",
          "identitystore:DescribeGroup",
          "identitystore:DescribeGroupMembership",
          "identitystore:DescribeUser",
          "identitystore:GetGroupId",
          "identitystore:GetGroupMembershipId",
          "identitystore:GetUserId",
          "identitystore:IsMemberInGroups",
          "identitystore:ListGroupMemberships",
          "identitystore:ListGroupMembershipsForMember",
          "identitystore:ListGroups",
          "identitystore:ListUsers",
          "identitystore:UpdateGroup",
          "identitystore:UpdateUser"
        ]
        Resource = [
          local.identity_store_arn,
          local.all_groups_arn,
          local.all_users_arn,
          local.all_memberships_arn,
        ]
      },
      {
        Sid    = "ProtectAdministrativeGroups"
        Effect = "Deny"
        Action = [
          "identitystore:CreateGroupMembership",
          "identitystore:DeleteGroup",
          "identitystore:DeleteGroupMembership",
          "identitystore:UpdateGroup"
        ]
        Resource = concat(
          [
            for group in aws_identitystore_group.administrators :
            "arn:${data.aws_partition.current.partition}:identitystore:::group/${group.group_id}"
          ],
          [
            for group in data.aws_identitystore_group.control_tower_protected :
            "arn:${data.aws_partition.current.partition}:identitystore:::group/${group.group_id}"
          ]
        )
      }
    ]
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "permission_set_admin" {
  # checkov:skip=CKV_AWS_289: This persona intentionally performs permission-set policy administration. Resource scoping, protected tags, assignment denies, MFA, and independent review constrain the residual permissions-management risk.
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permission_set_admin.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPermissionSetDefinitions"
        Effect = "Allow"
        Action = [
          "sso:DescribePermissionSet",
          "sso:DescribePermissionSetProvisioningStatus",
          "sso:GetInlinePolicyForPermissionSet",
          "sso:GetPermissionsBoundaryForPermissionSet",
          "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
          "sso:ListManagedPoliciesInPermissionSet",
          "sso:ListPermissionSets",
          "sso:ListPermissionSetsProvisionedToAccount",
          "sso:ListTagsForResource"
        ]
        Resource = [
          local.instance_arn,
          local.permission_set_wildcard,
          local.account_wildcard,
        ]
      },
      {
        Sid    = "ManageUnprotectedPermissionSetDefinitions"
        Effect = "Allow"
        Action = [
          "sso:AttachCustomerManagedPolicyReferenceToPermissionSet",
          "sso:AttachManagedPolicyToPermissionSet",
          "sso:CreatePermissionSet",
          "sso:DeleteInlinePolicyFromPermissionSet",
          "sso:DeletePermissionsBoundaryFromPermissionSet",
          "sso:DeletePermissionSet",
          "sso:DetachCustomerManagedPolicyReferenceFromPermissionSet",
          "sso:DetachManagedPolicyFromPermissionSet",
          "sso:PutInlinePolicyToPermissionSet",
          "sso:PutPermissionsBoundaryToPermissionSet",
          "sso:TagResource",
          "sso:UntagResource",
          "sso:UpdatePermissionSet"
        ]
        Resource = [
          local.instance_arn,
          local.permission_set_wildcard,
        ]
      },
      {
        Sid    = "ProtectAdministrativePermissionSets"
        Effect = "Deny"
        Action = [
          "sso:AttachCustomerManagedPolicyReferenceToPermissionSet",
          "sso:AttachManagedPolicyToPermissionSet",
          "sso:DeleteInlinePolicyFromPermissionSet",
          "sso:DeletePermissionsBoundaryFromPermissionSet",
          "sso:DeletePermissionSet",
          "sso:DetachCustomerManagedPolicyReferenceFromPermissionSet",
          "sso:DetachManagedPolicyFromPermissionSet",
          "sso:PutInlinePolicyToPermissionSet",
          "sso:PutPermissionsBoundaryToPermissionSet",
          "sso:TagResource",
          "sso:UntagResource",
          "sso:UpdatePermissionSet"
        ]
        Resource = local.permission_set_wildcard
        Condition = {
          StringEquals = {
            "aws:ResourceTag/SecurityBoundary" = "Protected"
          }
        }
      },
      {
        Sid    = "NoAccountAssignmentAdministration"
        Effect = "Deny"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "access_assignment_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.access_assignment_admin.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadIdentityCenterAssignments"
        Effect = "Allow"
        Action = [
          "sso:DescribeAccountAssignmentCreationStatus",
          "sso:DescribeAccountAssignmentDeletionStatus",
          "sso:DescribePermissionSet",
          "sso:ListAccountAssignmentCreationStatus",
          "sso:ListAccountAssignmentDeletionStatus",
          "sso:ListAccountAssignments",
          "sso:ListAccountAssignmentsForPrincipal",
          "sso:ListPermissionSets",
          "sso:ListPermissionSetsProvisionedToAccount"
        ]
        Resource = [
          local.instance_arn,
          local.permission_set_wildcard,
          local.account_wildcard,
        ]
      },
      {
        Sid    = "ReadIdentityStore"
        Effect = "Allow"
        Action = [
          "identitystore:DescribeGroup",
          "identitystore:DescribeUser",
          "identitystore:GetGroupId",
          "identitystore:GetUserId",
          "identitystore:ListGroups",
          "identitystore:ListUsers"
        ]
        Resource = [
          local.identity_store_arn,
          local.all_groups_arn,
          local.all_users_arn,
        ]
      },
      {
        Sid    = "DiscoverInstancesAndAccounts"
        Effect = "Allow"
        Action = [
          "sso:ListInstances",
          "organizations:DescribeOrganization",
          "organizations:ListAccounts",
          "organizations:ListAccountsForParent",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListRoots"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageAssignmentsInMemberAccounts"
        Effect = "Allow"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = local.account_wildcard
      },
      {
        Sid    = "ManageAssignmentsThroughCurrentInstance"
        Effect = "Allow"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = local.instance_arn
      },
      {
        Sid    = "AssignOnlyDelegatedPermissionSets"
        Effect = "Allow"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = local.permission_set_wildcard
        Condition = {
          StringEquals = {
            "aws:ResourceTag/AssignmentDelegation" = "Allowed"
          }
        }
      },
      {
        Sid    = "NoManagementAccountAssignments"
        Effect = "Deny"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = local.management_account_arn
      },
      {
        Sid    = "NoProtectedPermissionSetAssignments"
        Effect = "Deny"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment"
        ]
        Resource = local.permission_set_wildcard
        Condition = {
          StringEquals = {
            "aws:ResourceTag/SecurityBoundary" = "Protected"
          }
        }
      },
      {
        Sid    = "NoPermissionSetDefinitionAdministration"
        Effect = "Deny"
        Action = [
          "sso:AttachCustomerManagedPolicyReferenceToPermissionSet",
          "sso:AttachManagedPolicyToPermissionSet",
          "sso:CreatePermissionSet",
          "sso:DeleteInlinePolicyFromPermissionSet",
          "sso:DeletePermissionsBoundaryFromPermissionSet",
          "sso:DeletePermissionSet",
          "sso:DetachCustomerManagedPolicyReferenceFromPermissionSet",
          "sso:DetachManagedPolicyFromPermissionSet",
          "sso:PutInlinePolicyToPermissionSet",
          "sso:PutPermissionsBoundaryToPermissionSet",
          "sso:UpdatePermissionSet"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssoadmin_account_assignment" "identity_store_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.identity_store_admin.arn
  principal_id       = aws_identitystore_group.administrators["identity_store"].group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "permission_set_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permission_set_admin.arn
  principal_id       = aws_identitystore_group.administrators["permission_set"].group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "access_assignment_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.access_assignment_admin.arn
  principal_id       = aws_identitystore_group.administrators["access_assignment"].group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}
