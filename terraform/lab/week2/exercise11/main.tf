# Curriculum: Core
locals {
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise11Role"
  path                 = "/week2/exercise11/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:PrincipalArn" = local.source_operator_role_arn_pattern
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise11Role"
    Exercise = "11"
  })
}
resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise11Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" }]
  })
}
output "role_arn" {
  value = aws_iam_role.exercise.arn
}

output "boundary_arn" {
  value = data.aws_iam_policy.lab_role_boundary.arn
}

output "policy_fixture_paths" {
  value = {
    overly_broad           = "${path.module}/policies/overly-broad.json"
    malformed              = "${path.module}/policies/malformed.json"
    questionable_condition = "${path.module}/policies/questionable-condition.json"
    least_privilege        = "${path.module}/policies/least-privilege.json"
  }
}

# Check blocks for policy fixtures
check "overly_broad_policy_fixture_exists" {
  assert {
    condition     = fileexists("${path.module}/policies/overly-broad.json")
    error_message = "overly-broad.json policy fixture is missing."
  }
}

check "malformed_policy_fixture_exists" {
  assert {
    condition     = fileexists("${path.module}/policies/malformed.json")
    error_message = "malformed.json policy fixture is missing."
  }
}

check "questionable_condition_policy_fixture_exists" {
  assert {
    condition     = fileexists("${path.module}/policies/questionable-condition.json")
    error_message = "questionable-condition.json policy fixture is missing."
  }
}

check "least_privilege_policy_fixture_exists" {
  assert {
    condition     = fileexists("${path.module}/policies/least-privilege.json")
    error_message = "least-privilege.json policy fixture is missing."
  }
}

check "least_privilege_policy_no_wildcard_action" {
  assert {
    condition     = !contains(jsondecode(file("${path.module}/policies/least-privilege.json")).Statement[0].Action, "*")
    error_message = "least-privilege.json should not contain wildcard actions."
  }
}

check "least_privilege_policy_no_wildcard_resource" {
  assert {
    condition     = !contains(jsondecode(file("${path.module}/policies/least-privilege.json")).Statement[0].Resource, "*")
    error_message = "least-privilege.json should not contain wildcard resources."
  }
}
