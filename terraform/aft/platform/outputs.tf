output "aft_management_account_id" {
  description = "AFT management account ID reported by the AFT module."
  value       = module.aft.aft_management_account_id
}

output "aft_admin_role_arn" {
  description = "AFT administrative role ARN."
  value       = module.aft.aft_admin_role_arn
}

output "account_request_repo_name" {
  description = "Configured AFT account-request repository name."
  value       = module.aft.account_request_repo_name
}

output "global_customizations_repo_name" {
  description = "Configured AFT global-customizations repository name."
  value       = module.aft.global_customizations_repo_name
}

output "account_customizations_repo_name" {
  description = "Configured AFT account-customizations repository name."
  value       = module.aft.account_customizations_repo_name
}

output "account_provisioning_customizations_repo_name" {
  description = "Configured AFT account-provisioning-customizations repository name."
  value       = module.aft.account_provisioning_customizations_repo_name
}
