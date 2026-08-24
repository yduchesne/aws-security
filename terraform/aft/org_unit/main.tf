locals {
  aws_control_tower_baseline_arn = "arn:${data.aws_partition.current.partition}:controltower:${var.home_region}::baseline/17BSJV3IGJ2QSGA2"
}

resource "aws_organizations_organizational_unit" "aft" {
  name      = var.aft_ou_name
  parent_id = var.organization_root_id

  tags = {
    Purpose = "AWS Control Tower Account Factory for Terraform"
  }

  lifecycle {
    precondition {
      condition     = var.landing_zone_drift_status == "IN_SYNC"
      error_message = "The existing Control Tower landing zone must report IN_SYNC before creating or changing the AFT OU."
    }
  }
}

resource "aws_controltower_baseline" "aft" {
  baseline_identifier = local.aws_control_tower_baseline_arn
  baseline_version    = var.control_tower_baseline_version
  target_identifier   = aws_organizations_organizational_unit.aft.arn

  parameters {
    key   = "IdentityCenterEnabledBaselineArn"
    value = var.identity_center_enabled_baseline_arn
  }

  # Replacing this resource temporarily removes Control Tower governance from
  # the AFT OU. Require an explicit, reviewed code change for any future
  # baseline replacement rather than allowing a version typo to unregister it.
  lifecycle {
    prevent_destroy = true
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
