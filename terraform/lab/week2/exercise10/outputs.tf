output "role_arn" {
  description = "ARN of the generic Exercise 10 role."
  value       = aws_iam_role.exercise.arn
}

output "analyzer_arn" {
  description = "ARN of the account-level IAM Access Analyzer."
  value       = aws_accessanalyzer_analyzer.exercise.arn
}

output "analyzer_name" {
  description = "Name of the account-level IAM Access Analyzer."
  value       = aws_accessanalyzer_analyzer.exercise.analyzer_name
}

output "bucket_name" {
  description = "Name of the disposable S3 fixture bucket."
  value       = aws_s3_bucket.exercise.id
}

output "bucket_arn" {
  description = "ARN of the disposable S3 fixture bucket."
  value       = aws_s3_bucket.exercise.arn
}
