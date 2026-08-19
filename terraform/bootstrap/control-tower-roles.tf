###############################################################################
# AWS Control Tower prerequisite IAM roles
#
# These roles are created in the AWS Organizations management account before
# aws_controltower_landing_zone is created.
#
# Landing Zone 4.0 does NOT require
# AWSControlTowerConfigAggregatorRoleForOrganizations.
###############################################################################

###############################################################################
# AWSControlTowerAdmin
#
# AWS Control Tower assumes this role to perform operations required to
# establish and maintain the landing zone.
###############################################################################

data "aws_iam_policy_document" "control_tower_admin_trust" {
  statement {
    sid     = "AllowControlTowerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["controltower.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_tower_admin" {
  name = "AWSControlTowerAdmin"
  path = "/service-role/"

  assume_role_policy = data.aws_iam_policy_document.control_tower_admin_trust.json

  description = "Service role used by AWS Control Tower to manage the landing zone."
}

###############################################################################
# Core AWS Control Tower service permissions
###############################################################################

resource "aws_iam_role_policy_attachment" "control_tower_admin_service_role_policy" {
  role       = aws_iam_role.control_tower_admin.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSControlTowerServiceRolePolicy"
}

###############################################################################
# IAM Identity Center integration
#
# Required because the landing zone manifest sets:
#
# accessManagement = {
#   enabled = true
# }
###############################################################################

resource "aws_iam_role_policy_attachment" "control_tower_identity_center_management" {
  role       = aws_iam_role.control_tower_admin.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSControlTowerIdentityCenterManagementPolicy"
}

###############################################################################
# Additional Control Tower admin permission required by AWS
###############################################################################

data "aws_iam_policy_document" "control_tower_admin_inline" {
  statement {
    sid       = "DescribeAvailabilityZones"
    effect    = "Allow"
    actions   = ["ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "control_tower_admin" {
  name   = "AWSControlTowerAdminPolicy"
  role   = aws_iam_role.control_tower_admin.id
  policy = data.aws_iam_policy_document.control_tower_admin_inline.json
}


###############################################################################
# AWSControlTowerCloudTrailRole
#
# AWS CloudTrail assumes this role to publish Control Tower CloudTrail events
# to CloudWatch Logs.
#
# Landing Zone 4.0 uses the AWS-managed
# AWSControlTowerCloudTrailRolePolicy rather than the older inline policy.
###############################################################################

data "aws_iam_policy_document" "control_tower_cloudtrail_trust" {
  statement {
    sid     = "AllowCloudTrailAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_tower_cloudtrail" {
  name = "AWSControlTowerCloudTrailRole"
  path = "/service-role/"

  assume_role_policy = data.aws_iam_policy_document.control_tower_cloudtrail_trust.json

  description = "Service role used by CloudTrail for AWS Control Tower logging."
}

resource "aws_iam_role_policy_attachment" "control_tower_cloudtrail" {
  role       = aws_iam_role.control_tower_cloudtrail.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSControlTowerCloudTrailRolePolicy"
}


###############################################################################
# AWSControlTowerStackSetRole
#
# AWS CloudFormation assumes this role to deploy Control Tower StackSets into
# governed member accounts.
#
# This role in turn assumes AWSControlTowerExecution in member accounts.
###############################################################################

data "aws_iam_policy_document" "control_tower_stackset_trust" {
  statement {
    sid     = "AllowCloudFormationAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudformation.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_tower_stackset" {
  name = "AWSControlTowerStackSetRole"
  path = "/service-role/"

  assume_role_policy = data.aws_iam_policy_document.control_tower_stackset_trust.json

  description = "Service role used by AWS CloudFormation to deploy AWS Control Tower StackSets."
}

data "aws_iam_policy_document" "control_tower_stackset_inline" {
  statement {
    sid     = "AssumeControlTowerExecutionRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    resources = [
      "arn:${data.aws_partition.current.partition}:iam::*:role/AWSControlTowerExecution"
    ]
  }
}

resource "aws_iam_role_policy" "control_tower_stackset" {
  name   = "AWSControlTowerStackSetRolePolicy"
  role   = aws_iam_role.control_tower_stackset.name
  policy = data.aws_iam_policy_document.control_tower_stackset_inline.json
}
