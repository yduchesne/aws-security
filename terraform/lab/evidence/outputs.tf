output "evidence_bucket_name" {
  description = "Name of the Log Archive S3 bucket receiving lab data-event logs."
  value       = aws_s3_bucket.evidence.id
}

output "evidence_bucket_arn" {
  description = "ARN of the lab evidence bucket."
  value       = aws_s3_bucket.evidence.arn
}

output "trail_arn" {
  description = "ARN of the customer-managed organization trail for lab S3 data events."
  value       = aws_cloudtrail.lab_s3_data_events.arn
}

output "organization_id" {
  description = "AWS Organizations ID used in CloudTrail evidence prefixes."
  value       = local.organization_id
}

output "lab_evidence_prefixes" {
  description = "Per-account S3 prefixes readable from the corresponding lab account's WorkloadLabAdministrator session."
  value = {
    for key, account_id in local.lab_accounts :
    key => "s3://${aws_s3_bucket.evidence.id}/AWSLogs/${local.organization_id}/${account_id}/"
  }
}
