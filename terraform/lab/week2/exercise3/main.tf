# Curriculum: Core
locals {
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise3Role"
  path                 = "/week2/exercise3/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.source_operator_role_arn }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise3Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" }]
  })
}
output "role_arn" {
  value = aws_iam_role.exercise.arn
}
