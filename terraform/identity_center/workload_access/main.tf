locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.current.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]

  test_users = {
    user1 = {
      email      = var.test_user1_email
      first_name = var.test_user1_first_name
      last_name  = var.test_user1_last_name
    }
    user2 = {
      email      = var.test_user2_email
      first_name = var.test_user2_first_name
      last_name  = var.test_user2_last_name
    }
  }

  groups = {
    viewers = {
      display_name = "WorkloadViewers"
      description  = "Provides approved view-only access to workload accounts."
    }
    security_auditors = {
      display_name = "WorkloadSecurityAuditors"
      description  = "Provides approved security-audit access to workload accounts."
    }
    developers = {
      display_name = "WorkloadDevelopers"
      description  = "Provides development capabilities in approved Dev workload accounts only."
    }
    test_operators = {
      display_name = "WorkloadTestOperators"
      description  = "Provides explicitly approved operational capabilities in Test workload accounts only."
    }
    production_operators = {
      display_name = "WorkloadProductionOperators"
      description  = "Provides explicitly approved operational capabilities in Prod workload accounts only."
    }
    lab_administrators = {
      display_name = "WorkloadLabAdministrators"
      description  = "Provides bounded lab administration in the explicitly approved Dev Lab and Test Lab accounts."
    }
    lab_baseline_administrators = {
      display_name = "WorkloadLabBaselineAdministrators"
      description  = "Provides tightly scoped administration in the context of lab setup (e.g.: creating permission boundaries)."
    }
  }

  permission_sets = {
    view_only = {
      name               = "WorkloadViewOnly"
      description        = "View-only workload access without write permissions."
      session_duration   = "PT4H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
    }
    security_audit = {
      name               = "WorkloadSecurityAudit"
      description        = "Security configuration and compliance audit access without remediation writes."
      session_duration   = "PT2H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SecurityAudit"
    }
    developer = {
      name               = "WorkloadDeveloper"
      description        = "Development access bounded away from identity, organization, and governance administration."
      session_duration   = "PT2H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
    }
    test_operator = {
      name               = "WorkloadTestOperator"
      description        = "Read-only Test access plus explicitly configured operational actions."
      session_duration   = "PT1H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
    }
    production_operator = {
      name               = "WorkloadProductionOperator"
      description        = "View-only Prod access plus explicitly configured operational actions."
      session_duration   = "PT1H"
      managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
    }
    lab_administrator = {
      name               = "WorkloadLabAdministrator"
      description        = "Bounded IAM, S3, STS, and narrowly scoped EC2 administration for approved Week 2 lab exercises."
      session_duration   = "PT1H"
      managed_policy_arn = null
    }
    lab_baseline_administrator = {
      name               = "WorkloadLabBaselineAdmin"
      description        = "Tightly scoped management of the persistent Week 2 lab-role permissions boundary."
      session_duration   = "PT1H"
      managed_policy_arn = null
    }
  }

  elevated_permission_set_keys = toset([
    "developer",
    "test_operator",
    "production_operator",
  ])

  explicitly_allowed_actions = {
    developer           = []
    test_operator       = var.test_operator_allowed_actions
    production_operator = var.production_operator_allowed_actions
  }

  # These denies remain effective even if an attached AWS managed policy gains
  # broader permissions or additional operational actions are configured.
  sensitive_administration_denies = [
    "account:*",
    "controltower:*",
    "iam:*",
    "identitystore:*",
    "organizations:*",
    "sso:*",
    "budgets:DeleteBudgetAction",
    "budgets:ModifyBudget",
    "cloudtrail:DeleteTrail",
    "cloudtrail:PutEventSelectors",
    "cloudtrail:StopLogging",
    "cloudtrail:UpdateTrail",
    "config:DeleteConfigurationRecorder",
    "config:DeleteDeliveryChannel",
    "config:StopConfigurationRecorder",
    "ec2:DisableEbsEncryptionByDefault",
    "guardduty:DeleteDetector",
    "guardduty:DisassociateFromAdministratorAccount",
    "guardduty:DisassociateMembers",
    "guardduty:StopMonitoringMembers",
    "kms:CreateGrant",
    "kms:DisableKey",
    "kms:PutKeyPolicy",
    "kms:RetireGrant",
    "kms:RevokeGrant",
    "kms:ScheduleKeyDeletion",
    "logs:DeleteLogGroup",
    "logs:DeleteRetentionPolicy",
    "securityhub:DeleteMembers",
    "securityhub:DisableSecurityHub",
    "securityhub:DisassociateFromAdministratorAccount",
    "securityhub:DisassociateMembers",
    "sts:AssumeRole*",
    "sts:SetSourceIdentity",
    "sts:TagSession",
  ]

  allowed_assignment_combinations = toset([
    "viewers:view_only:dev",
    "viewers:view_only:test",
    "viewers:view_only:prod",
    "security_auditors:security_audit:dev",
    "security_auditors:security_audit:test",
    "security_auditors:security_audit:prod",
    "developers:developer:dev",
    "test_operators:test_operator:test",
    "production_operators:production_operator:prod",
    "lab_administrators:lab_administrator:dev",
    "lab_administrators:lab_administrator:test",
  ])

  lab_account_ids = toset(values(var.lab_account_ids))
  lab_role_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:iam::${account_id}:role${var.lab_role_path_prefix}*"
  ]
  lab_boundary_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:iam::${account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
  ]
  lab_exercise_instance_profile_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:iam::${account_id}:instance-profile/week*/exercise*/*"
  ]
  lab_exercise_role_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:iam::${account_id}:role/week*/exercise*/*"
  ]
  lab_oidc_provider_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:iam::${account_id}:oidc-provider/*"
  ]
  lab_ec2_vpc_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:vpc/*"
  ]
  lab_ec2_security_group_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:security-group/*"
  ]
  lab_ec2_resource_arns = flatten([
    for account_id in local.lab_account_ids : [
      "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.home_region}:${account_id}:volume/*",
    ]
  ])
  lab_bucket_arns = [
    "arn:${data.aws_partition.current.partition}:s3:::${var.lab_bucket_name_prefix}*",
    "arn:${data.aws_partition.current.partition}:s3:::${var.lab_bucket_name_prefix}*/*",
  ]
  lab_exercise10_analyzer_arns = [
    for account_id in local.lab_account_ids :
    "arn:${data.aws_partition.current.partition}:access-analyzer:*:${account_id}:analyzer/Week2Exercise10Analyzer"
  ]
  lab_evidence_bucket_name = "aws-security-lab-evidence-${var.management_account_id}"
  lab_evidence_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.lab_evidence_bucket_name}"
  lab_evidence_prefixes = [
    for account_id in local.lab_account_ids :
    "AWSLogs/${data.aws_organizations_organization.current.id}/${account_id}/*"
  ]
  lab_evidence_object_arns = [
    for prefix in local.lab_evidence_prefixes :
    "${local.lab_evidence_bucket_arn}/${prefix}"
  ]
}

# The parent identity_center root owns this named human. This root only looks it
# up so workload-specific access can be managed without duplicating ownership.
data "aws_identitystore_user" "lab_admin" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.sso_lab_admin_email
    }
  }
}

resource "aws_identitystore_user" "test" {
  for_each = local.test_users

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
      condition     = var.test_user1_email != var.test_user2_email
      error_message = "test_user1_email and test_user2_email must identify distinct Identity Center users."
    }

    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.management_account_id
      error_message = "Test Identity Center users must be managed from the Organizations management account."
    }
  }
}

resource "aws_identitystore_group" "workload" {
  for_each = local.groups

  identity_store_id = local.identity_store_id
  display_name      = each.value.display_name
  description       = each.value.description

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.management_account_id
      error_message = "Workload Identity Center resources must be managed from the Organizations management account."
    }
  }
}

resource "aws_identitystore_group_membership" "lab_baseline_administrator" {
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.workload["lab_baseline_administrators"].group_id
  member_id         = data.aws_identitystore_user.lab_admin.user_id

  lifecycle {
    precondition {
      condition = !contains([
        var.test_user1_email,
        var.test_user2_email,
      ], var.sso_lab_admin_email)
      error_message = "The lab baseline administrator must be distinct from both manually operated exercise test users."
    }
  }
}

resource "aws_ssoadmin_permission_set" "workload" {
  for_each = local.permission_sets

  instance_arn     = local.instance_arn
  name             = each.value.name
  description      = each.value.description
  session_duration = each.value.session_duration

  tags = merge(
    var.common_tags,
    {
      AccessDomain = "Workloads"
    },
    each.key == "lab_baseline_administrator" ? {
      SecurityBoundary = "Protected"
      } : {
      AssignmentDelegation = "Allowed"
    }
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "workload" {
  for_each = {
    for key, permission_set in local.permission_sets : key => permission_set
    if permission_set.managed_policy_arn != null
  }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.key].arn
  managed_policy_arn = each.value.managed_policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "elevated_boundary" {
  for_each = local.elevated_permission_set_keys

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.key].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.explicitly_allowed_actions[each.key]) > 0 ? [
        {
          Sid      = "ExplicitOperationalActions"
          Effect   = "Allow"
          Action   = local.explicitly_allowed_actions[each.key]
          Resource = "*"
        }
      ] : [],
      [
        {
          Sid      = "DenySensitiveAdministration"
          Effect   = "Deny"
          Action   = local.sensitive_administration_denies
          Resource = "*"
        }
      ]
    )
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "lab_baseline_administrator" {
  # checkov:skip=CKV_AWS_289: This dedicated one-hour persona intentionally manages only the exact Week 2 boundary policies in two allowlisted lab accounts; no general IAM or workload administration is granted.
  for_each = length(var.lab_account_ids) == 2 ? { enabled = true } : {}

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload["lab_baseline_administrator"].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCurrentIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid    = "CreateAndTagLabBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:TagPolicy",
        ]
        Resource = local.lab_boundary_arns
      },
      {
        Sid    = "ReadLabBoundary"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListEntitiesForPolicy",
          "iam:ListPolicyTags",
          "iam:ListPolicyVersions",
        ]
        Resource = local.lab_boundary_arns
      },
      {
        Sid    = "UpdateLabBoundaryVersions"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = local.lab_boundary_arns
      },
      {
        Sid    = "DenyUnrelatedAdministration"
        Effect = "Deny"
        Action = [
          "account:*",
          "controltower:*",
          "identitystore:*",
          "organizations:*",
          "sso:*",
          "iam:AddUserToGroup",
          "iam:AttachGroupPolicy",
          "iam:AttachRolePolicy",
          "iam:AttachUserPolicy",
          "iam:CreateAccessKey",
          "iam:CreateGroup",
          "iam:CreateInstanceProfile",
          "iam:CreateLoginProfile",
          "iam:CreateRole",
          "iam:CreateSAMLProvider",
          "iam:CreateServiceLinkedRole",
          "iam:CreateUser",
          "iam:PassRole",
          "iam:PutGroupPolicy",
          "iam:PutRolePolicy",
          "iam:PutUserPolicy",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssoadmin_permission_set_inline_policy" "lab_administrator" {
  for_each = length(var.lab_account_ids) == 2 ? { enabled = true } : {}

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload["lab_administrator"].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCurrentIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid      = "CreateBoundedLabRoles"
        Effect   = "Allow"
        Action   = "iam:CreateRole"
        Resource = local.lab_role_arns
        Condition = {
          ArnEquals = {
            "iam:PermissionsBoundary" = local.lab_boundary_arns
          }
        }
      },
      {
        Sid    = "ManageBoundedLabRoles"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRolePolicies",
          "iam:ListRoleTags",
          "iam:PutRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
        ]
        Resource = local.lab_role_arns
      },
      {
        Sid      = "AttachOnlyApprovedBoundary"
        Effect   = "Allow"
        Action   = "iam:PutRolePermissionsBoundary"
        Resource = local.lab_role_arns
        Condition = {
          ArnEquals = {
            "iam:PermissionsBoundary" = local.lab_boundary_arns
          }
        }
      },
      {
        Sid    = "ReadApprovedBoundary"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
        ]
        Resource = local.lab_boundary_arns
      },
      {
        Sid      = "AssumeOnlyLabRoles"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.lab_role_arns
      },
      {
        Sid      = "ReadLabAuditEvidence"
        Effect   = "Allow"
        Action   = "cloudtrail:LookupEvents"
        Resource = "*"
      },
      {
        Sid    = "ReadExercise10AccessAnalyzer"
        Effect = "Allow"
        Action = [
          "access-analyzer:GetAnalyzer",
          "access-analyzer:GetFinding",
          "access-analyzer:ListArchiveRules",
          "access-analyzer:ListFindings",
          "access-analyzer:ListTagsForResource",
        ]
        Resource = local.lab_exercise10_analyzer_arns
      },
      {
        Sid    = "ListExercise10AccessAnalyzers"
        Effect = "Allow"
        Action = [
          "access-analyzer:ListAnalyzers",
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageExercise10AccessAnalyzer"
        Effect = "Allow"
        Action = [
          "access-analyzer:CreateAnalyzer",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Name" = "Week2Exercise10Analyzer"
          }
        }
      },
      {
        Sid    = "ManageExercise10AccessAnalyzerResource"
        Effect = "Allow"
        Action = [
          "access-analyzer:DeleteAnalyzer",
          "access-analyzer:GetAnalyzer",
          "access-analyzer:TagResource",
          "access-analyzer:UntagResource",
        ]
        Resource = local.lab_exercise10_analyzer_arns
      },
      {
        Sid    = "AllowAccessAnalyzerServiceLinkedRole"
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "access-analyzer.amazonaws.com"
          }
        }
      },
      {
        Sid    = "DenyOtherServiceLinkedRoles"
        Effect = "Deny"
        Action = [
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "iam:AWSServiceName" = "access-analyzer.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ManageNamedLabBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucketEncryption",
          "s3:DeleteBucketOwnershipControls",
          "s3:DeleteBucketPublicAccessBlock",
          "s3:DeleteBucketTagging",
          "s3:DeleteBucketWebsite",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketLocation",
          "s3:GetBucketLogging",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketOwnershipControls",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketWebsite",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:GetObjectAttributes",
          "s3:GetObjectTagging",
          "s3:GetObjectVersion",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:PutObject",
          "s3:PutObjectTagging",
        ]
        Resource = local.lab_bucket_arns
      },
      {
        Sid    = "ManageLabExerciseOidcProviders"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
        ]
        Resource = local.lab_oidc_provider_arns
      },
      {
        Sid    = "ManageLabExerciseInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
        ]
        Resource = local.lab_exercise_instance_profile_arns
      },
      {
        Sid      = "PassOnlyBoundedLabExerciseRolesToEC2"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.lab_exercise_role_arns
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ReadEC2ForLabExercises"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceCreditSpecifications",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroupRules",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcs",
          "ec2:GetConsoleOutput",
        ]
        Resource = "*"
      },
      {
        Sid    = "LaunchLabExerciseInstances"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        # RunInstances is a multi-resource API. AWS evaluates it against each
        # resource involved in the launch, including the network interface.
        # Resource-level restrictions and request-tag conditions are not
        # reliable across those authorization contexts. The permission set is
        # assigned only to the allowlisted lab accounts; exercise lifecycle
        # mutations below require an Exercise resource tag.
        Resource = "*"
      },
      {
        Sid    = "CreateLabExerciseSecurityGroups"
        Effect = "Allow"
        Action = "ec2:CreateSecurityGroup"
        # EC2 has returned both vpc/* and security-group/* as the authorization
        # resource for CreateSecurityGroup across API/provider versions. Keep
        # both account-scoped resource forms. Terraform applies the exercise
        # tag in a subsequent CreateTags request, so tagging is separately
        # restricted to creation-time exercise requests below.
        Resource = concat(local.lab_ec2_vpc_arns, local.lab_ec2_security_group_arns)
      },
      {
        Sid      = "TagLabExerciseResourcesOnlyAtCreation"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = local.lab_ec2_resource_arns
        Condition = {
          StringLike = {
            "aws:RequestTag/Exercise" = "*"
          }
          StringEquals = {
            "ec2:CreateAction" = ["CreateSecurityGroup", "RunInstances"]
          }
        }
      },
      {
        Sid    = "ManageTaggedLabExerciseResources"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:DeleteSecurityGroup",
          "ec2:RebootInstances",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/Exercise" = "*"
          }
        }
      },
      {
        Sid      = "ReadLabEvidenceBucketMetadata"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = local.lab_evidence_bucket_arn
      },
      {
        Sid      = "ListOnlyAssignedLabEvidencePrefixes"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.lab_evidence_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = local.lab_evidence_prefixes
          }
        }
      },
      {
        Sid    = "ReadOnlyAssignedLabEvidence"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ]
        Resource = local.lab_evidence_object_arns
      },
      {
        Sid    = "DenyBoundaryAndCredentialEscalation"
        Effect = "Deny"
        Action = [
          "iam:AddUserToGroup",
          "iam:AttachGroupPolicy",
          "iam:AttachRolePolicy",
          "iam:AttachUserPolicy",
          "iam:CreateAccessKey",
          "iam:CreateGroup",
          "iam:CreateLoginProfile",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:CreateSAMLProvider",
          "iam:CreateUser",
          "iam:DeleteRolePermissionsBoundary",
          "iam:PutGroupPolicy",
          "iam:PutUserPermissionsBoundary",
          "iam:PutUserPolicy",
          "iam:SetDefaultPolicyVersion",
          "iam:UpdateAccessKey",
          "iam:UpdateLoginProfile",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyCentralGovernanceAdministration"
        Effect = "Deny"
        Action = [
          "account:*",
          "billing:*",
          "budgets:*",
          "controltower:*",
          "identitystore:*",
          "organizations:*",
          "sso:*",
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder",
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromAdministratorAccount",
          "guardduty:StopMonitoringMembers",
          "kms:CreateGrant",
          "kms:DisableKey",
          "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion",
          "logs:DeleteLogGroup",
          "logs:DeleteRetentionPolicy",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromAdministratorAccount",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssoadmin_account_assignment" "lab_baseline_administrator" {
  for_each = var.lab_account_ids

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload["lab_baseline_administrator"].arn
  principal_id       = aws_identitystore_group.workload["lab_baseline_administrators"].group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"

  lifecycle {
    precondition {
      condition     = contains(["dev", "test"], each.key)
      error_message = "Lab baseline administration may target only the allowlisted Dev Lab and Test Lab accounts."
    }

    precondition {
      condition     = each.value != var.management_account_id
      error_message = "Lab baseline administration must not be assigned to the Organizations management account."
    }
  }
}

resource "aws_ssoadmin_account_assignment" "workload" {
  for_each = var.account_assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.workload[each.value.permission_set_key].arn
  principal_id       = aws_identitystore_group.workload[each.value.group_key].group_id
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"

  lifecycle {
    precondition {
      condition = contains(
        local.allowed_assignment_combinations,
        "${each.value.group_key}:${each.value.permission_set_key}:${each.value.environment}"
      )
      error_message = "The requested group, permission set, and environment assignment is not in the approved workload access matrix."
    }

    precondition {
      condition     = each.value.account_id != var.management_account_id
      error_message = "Workload permission sets must not be assigned to the Organizations management account."
    }

    precondition {
      condition = (
        each.value.permission_set_key != "lab_administrator" ||
        each.value.account_id == lookup(var.lab_account_ids, each.value.environment, "")
      )
      error_message = "WorkloadLabAdministrator may be assigned only to the explicitly allowlisted Dev Lab or Test Lab account for the selected environment."
    }
  }
}
