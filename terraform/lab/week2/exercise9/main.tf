# Curriculum: Core
locals {
  oidc_condition_key = trimprefix(var.oidc_url, "https://")
  boundary_arn       = "arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:policy/week2/WorkloadLabRoleBoundary"
}

resource "aws_iam_openid_connect_provider" "exercise" {
  url             = var.oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.oidc_thumbprint]

  tags = merge(var.common_tags, {
    Name      = "Week2Exercise9OidcProvider"
    Exercise  = "9"
    OidcClaim = var.oidc_subject
  })
}

resource "aws_iam_role" "exercise" {
  name                 = "Week2Exercise9Role"
  path                 = "/week2/exercise9/"
  permissions_boundary = local.boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.exercise.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_condition_key}:aud" = "sts.amazonaws.com"
          "${local.oidc_condition_key}:sub" = var.oidc_subject
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name     = "Week2Exercise9Role"
    Exercise = "9"
  })
}
resource "aws_iam_role_policy" "exercise" {
  role = aws_iam_role.exercise.id
  name = "Exercise9Policy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" }]
  })
}
output "role_arn" {
  description = "OIDC-federated Exercise 9 role ARN."
  value       = aws_iam_role.exercise.arn
}

output "oidc_provider_arn" {
  description = "Exercise 9 OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.exercise.arn
}

output "oidc_subject" {
  description = "Exact subject claim trusted by the Exercise 9 role."
  value       = var.oidc_subject
}
