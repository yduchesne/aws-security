locals {
  boundary_policy = templatefile("${path.module}/policies/workload-lab-role-boundary.json.tftpl", {
    partition              = data.aws_partition.current.partition
    dev_lab_account_id     = var.lab_account_ids.dev
    test_lab_account_id    = var.lab_account_ids.test
    lab_bucket_name_prefix = var.lab_bucket_name_prefix
  })
}

resource "aws_iam_policy" "source_lab_role_boundary" {
  provider = aws.source

  name        = var.lab_role_boundary_name
  path        = var.lab_role_boundary_path
  description = "Maximum permissions for bounded Week 2 lab roles."
  policy      = local.boundary_policy

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_policy" "target_lab_role_boundary" {
  provider = aws.target

  name        = var.lab_role_boundary_name
  path        = var.lab_role_boundary_path
  description = "Maximum permissions for bounded Week 2 lab roles."
  policy      = local.boundary_policy

  lifecycle {
    prevent_destroy = true
  }
}

check "provider_accounts_match" {
  assert {
    condition     = data.aws_caller_identity.source.account_id == var.lab_account_ids.dev
    error_message = "The source provider authenticated to an account other than the allowlisted Dev Lab account."
  }

  assert {
    condition     = data.aws_caller_identity.target.account_id == var.lab_account_ids.test
    error_message = "The target provider authenticated to an account other than the allowlisted Test Lab account."
  }
}
