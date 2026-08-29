# Curriculum: Core
locals {
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy${var.lab_role_boundary_path}${var.lab_role_boundary_name}"
}

data "aws_iam_policy" "lab_role_boundary" {
  arn = local.boundary_arn
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise5Role"
  path                 = "/week2/exercise5/"
  permissions_boundary = data.aws_iam_policy.lab_role_boundary.arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_caller_identity.current.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise5Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" }]
  })
}
output "role_arn" {
  value = aws_iam_role.exercise.arn
}
