output "role_arn" {
  description = "ARN of the Exercise 14 role."
  value       = aws_iam_role.exercise.arn
}

output "permissions_boundary_arn" {
  description = "ARN of the baseline-owned permissions boundary attached to the role."
  value       = data.aws_iam_policy.lab_role_boundary.arn
}

output "admin_policy_name" {
  description = "Name of the AdministratorAccess-equivalent inline policy."
  value       = aws_iam_role_policy.exercise.name
}
