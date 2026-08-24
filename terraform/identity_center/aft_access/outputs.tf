output "aft_platform_administrators_group_id" {
  description = "Identity Store group ID for AFTPlatformAdministrators."
  value       = aws_identitystore_group.aft_platform_administrators.group_id
}

output "aft_platform_administration_permission_set_arn" {
  description = "ARN of the AFTPlatformAdministration permission set."
  value       = aws_ssoadmin_permission_set.aft_platform_administration.arn
}

output "aft_management_account_id" {
  description = "AWS account receiving the AFT platform administration assignment."
  value       = var.aft_management_account_id
}
