# Curriculum: Optional
locals {
  source_operator_role_path_prefix = var.aws_region == "us-east-1" ? "/aws-reserved/sso.amazonaws.com/" : "/aws-reserved/sso.amazonaws.com/${var.aws_region}/"
  source_operator_role_arn_pattern = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:role${local.source_operator_role_path_prefix}AWSReservedSSO_WorkloadLabAdministrator_*"
  boundary_arn                     = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise14Role"
  path                 = "/week2/exercise14/"
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
    Name     = "Week2Exercise14Role"
    Exercise = "14"
  })
}

resource "aws_iam_role_policy" "exercise" {
  # checkov:skip=CKV_AWS_288: Intentional Exercise 14 fixture: the wildcard identity policy models AdministratorAccess so the separately managed WorkloadLabRoleBoundary can be demonstrated as the effective ceiling. The role is disposable, restricted to /week2/exercise14/, assumable only by the approved WorkloadLabAdministrator SSO role, and must be destroyed after testing.
  # checkov:skip=CKV_AWS_63: Intentional Exercise 14 fixture: Action = ["*"] is the subject of the experiment, proving that a broad identity Allow does not bypass the attached baseline permissions boundary. This policy is not a production permission set and the role cannot be assumed outside the approved Dev Lab trust path.
  # checkov:skip=CKV_AWS_62: Intentional AdministratorAccess-equivalent replica required by Exercise 14 to compare identity-policy Allow with boundary-limited effective permissions. The role has the immutable baseline boundary /week2/WorkloadLabRoleBoundary, a constrained /week2/exercise14/ path, and disposable lab ownership.
  # checkov:skip=CKV_AWS_355: Intentional wildcard Resource for the AdministratorAccess-equivalent teaching fixture; resource narrowing would change the policy semantics under test. The role is bounded by the baseline policy, restricted by trust to the approved lab SSO role, and limited to the disposable Dev Lab exercise lifecycle.
  # checkov:skip=CKV_AWS_289: Intentional Exercise 14 policy replica includes permissions-management capabilities solely to test that the baseline permissions boundary prevents them from becoming effective. The boundary is owned by the separate trusted baseline root and the lab operator cannot mutate or detach it.
  # checkov:skip=CKV_AWS_290: Intentional wildcard write Allow required to model AdministratorAccess in this disposable authorization exercise. The role is protected by the pre-provisioned boundary, fixed exercise path and tags, restricted trust, and Dev Lab account provider allowlist; it is not a reusable workload role.
  # checkov:skip=CKV_AWS_287: Intentional Exercise 14 AdministratorAccess-equivalent identity policy used to test credential-related actions being capped by the permissions boundary. No credentials are created or stored by the fixture, and the role is disposable and restricted to the approved lab operator trust.
  # checkov:skip=CKV_AWS_286: Intentional privilege-escalation fixture: the exercise must show that an identity Allow of * cannot exceed the baseline boundary. Boundary ownership remains in terraform/lab/week2/baseline, role creation is constrained by the lab permission set, and this root does not alter the boundary.
  # checkov:skip=CKV2_AWS_40: Intentional full-IAM-policy replica for Exercise 14's boundary-ceiling lesson. Effective access remains bounded by /week2/WorkloadLabRoleBoundary and the role's restricted trust/path; this disposable role is destroyed after evidence collection.
  role = aws_iam_role.exercise.id
  name = "Exercise14Policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AdministratorAccessEquivalent"
      Effect   = "Allow"
      Action   = ["*"]
      Resource = ["*"]
    }]
  })
}

check "provider_account_matches_source" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.source_account_id
    error_message = "The provider authenticated to an account other than source_account_id."
  }
}

check "role_has_baseline_boundary" {
  assert {
    condition     = aws_iam_role.exercise.permissions_boundary == data.aws_iam_policy.lab_role_boundary.arn
    error_message = "The exercise role must use the pre-provisioned lab permissions boundary."
  }
}

check "identity_policy_is_exact_administrator_replica" {
  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.exercise.policy)) == jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "AdministratorAccessEquivalent"
        Effect   = "Allow"
        Action   = ["*"]
        Resource = ["*"]
      }]
    })
    error_message = "Exercise14Policy must remain exactly one AdministratorAccess-equivalent Allow statement."
  }
}

check "boundary_is_baseline_named_policy" {
  assert {
    condition     = data.aws_iam_policy.lab_role_boundary.arn == local.boundary_arn
    error_message = "The exercise must reference the named baseline boundary without owning it."
  }
}
