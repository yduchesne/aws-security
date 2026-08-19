output "identity_center_instance_arn" {
  description = "Organization IAM Identity Center instance ARN."
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "Organization IAM Identity Store ID."
  value       = local.identity_store_id
}

output "administrative_group_ids" {
  description = "IDs of the Terraform-managed administrative groups."
  value = {
    for key, group in aws_identitystore_group.administrators :
    key => group.group_id
  }
}

output "administrative_permission_set_arns" {
  description = "ARNs of the Terraform-managed administrative permission sets."
  value = {
    identity_store    = aws_ssoadmin_permission_set.identity_store_admin.arn
    permission_set    = aws_ssoadmin_permission_set.permission_set_admin.arn
    access_assignment = aws_ssoadmin_permission_set.access_assignment_admin.arn
  }
}
