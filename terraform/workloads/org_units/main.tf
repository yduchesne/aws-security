locals {
  aws_control_tower_baseline_arn = "arn:${data.aws_partition.current.partition}:controltower:${var.home_region}::baseline/17BSJV3IGJ2QSGA2"
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = var.workloads_ou_name
  parent_id = var.organization_root_id

  tags = {
    Purpose = "AWS workload accounts"
  }

  lifecycle {
    precondition {
      condition     = var.landing_zone_drift_status == "IN_SYNC"
      error_message = "The existing Control Tower landing zone must report IN_SYNC before creating or changing the workload OU hierarchy."
    }
  }
}

resource "aws_controltower_baseline" "workloads" {
  baseline_identifier = local.aws_control_tower_baseline_arn
  baseline_version    = var.control_tower_baseline_version
  target_identifier   = aws_organizations_organizational_unit.workloads.arn

  parameters {
    key   = "IdentityCenterEnabledBaselineArn"
    value = var.identity_center_enabled_baseline_arn
  }

  # Replacing this resource temporarily removes Control Tower governance.
  # Require an explicit, reviewed code change for any baseline replacement.
  lifecycle {
    prevent_destroy = true
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

resource "aws_organizations_organizational_unit" "environment" {
  for_each = var.environment_ou_names

  name      = each.value
  parent_id = aws_organizations_organizational_unit.workloads.id

  tags = {
    Purpose     = "AWS ${each.value} workload accounts"
    Environment = each.value
  }

  # Establish governance on the parent before extending the governed hierarchy.
  depends_on = [aws_controltower_baseline.workloads]
}

resource "aws_controltower_baseline" "environment" {
  for_each = aws_organizations_organizational_unit.environment

  baseline_identifier = local.aws_control_tower_baseline_arn
  baseline_version    = var.control_tower_baseline_version
  target_identifier   = each.value.arn

  parameters {
    key   = "IdentityCenterEnabledBaselineArn"
    value = var.identity_center_enabled_baseline_arn
  }

  # Replacing any environment baseline temporarily removes Control Tower
  # governance from an AFT provisioning target.
  lifecycle {
    prevent_destroy = true
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
