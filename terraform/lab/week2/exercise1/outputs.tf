output "approved_caller_role_arn" {
  description = "ARN of the approved source-account caller role."
  value       = aws_iam_role.caller.arn
}

output "untrusted_caller_role_arn" {
  description = "ARN of the source-account role that the target role does not trust."
  value       = aws_iam_role.untrusted_caller.arn
}

output "target_read_role_arn" {
  description = "ARN to pass to aws sts assume-role during the exercise."
  value       = aws_iam_role.target_read.arn
}

output "approved_bucket_name" {
  description = "Bucket on which list and selected object reads should succeed."
  value       = aws_s3_bucket.approved.id
}

output "approved_object_uri" {
  description = "S3 URI of the object the target role may read."
  value       = "s3://${aws_s3_bucket.approved.id}/${aws_s3_object.approved.key}"
}

output "unrelated_bucket_name" {
  description = "Bucket against which the unrelated-resource denial should be tested."
  value       = aws_s3_bucket.unrelated.id
}
