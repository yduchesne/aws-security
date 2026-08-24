output "test_user_ids" {
  description = "Identity Store IDs of the manually operated test users, keyed by user label."
  value       = { for key, user in aws_identitystore_user.test : key => user.user_id }
}

output "workload_group_ids" {
  description = "IDs of the project-owned workload groups, keyed by group role."
  value       = { for key, group in aws_identitystore_group.workload : key => group.group_id }
}

output "workload_permission_set_arns" {
  description = "ARNs of the project-owned workload permission sets, keyed by capability."
  value       = { for key, permission_set in aws_ssoadmin_permission_set.workload : key => permission_set.arn }
}

output "workload_account_assignments" {
  description = "Configured workload account assignments, keyed by the caller-provided stable identifier."
  value = {
    for key, assignment in var.account_assignments : key => {
      account_id         = assignment.account_id
      environment        = assignment.environment
      group_key          = assignment.group_key
      permission_set_key = assignment.permission_set_key
    }
  }
}
