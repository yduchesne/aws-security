output "source_lab_role_boundary_arn" {
  description = "ARN of WorkloadLabRoleBoundary in the Dev Lab/source account."
  value       = aws_iam_policy.source_lab_role_boundary.arn
}

output "target_lab_role_boundary_arn" {
  description = "ARN of WorkloadLabRoleBoundary in the Test Lab/target account."
  value       = aws_iam_policy.target_lab_role_boundary.arn
}
