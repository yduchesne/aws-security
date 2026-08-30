output "role_arn" {
  description = "ARN of the deliberately over-granted Exercise 12 role."
  value       = aws_iam_role.exercise.arn
}

output "analyzer_arn" {
  description = "ARN of the account-level IAM Access Analyzer unused-access analyzer."
  value       = aws_accessanalyzer_analyzer.exercise.arn
}

output "analyzer_name" {
  description = "Name of the account-level IAM Access Analyzer unused-access analyzer."
  value       = aws_accessanalyzer_analyzer.exercise.analyzer_name
}

output "unused_access_age" {
  description = "Configured inactivity tracking period in days."
  value       = var.unused_access_age
}

output "exercise_policy_actions" {
  description = "Actions granted by the exercise role identity policy."
  value       = local.exercise_policy_actions
}
