output "role_arn" {
  description = "ARN of the Exercise 13 role."
  value       = aws_iam_role.exercise.arn
}

output "bucket_name" {
  description = "Name of the disposable S3 fixture bucket."
  value       = aws_s3_bucket.exercise.id
}

output "bucket_arn" {
  description = "ARN of the disposable S3 fixture bucket."
  value       = aws_s3_bucket.exercise.arn
}

output "scp_policy_arn" {
  description = "ARN of the exercise SCP, or null while the deny is disabled."
  value       = one(aws_organizations_policy.exercise_scp_deny[*].arn)
}

output "scp_deny_enabled" {
  description = "Whether the exercise SCP deny is enabled."
  value       = var.scp_deny_enabled
}

output "scp_deny_actions" {
  description = "Actions denied by the exercise SCP fixture."
  value       = var.scp_deny_actions
}
