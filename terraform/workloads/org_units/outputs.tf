output "landing_zone_arn" {
  description = "Existing landing-zone ARN used as this root's prerequisite."
  value       = var.landing_zone_arn
}

output "workloads_ou_id" {
  description = "Organizations ID of the root-level Workloads OU."
  value       = aws_organizations_organizational_unit.workloads.id
}

output "workloads_ou_arn" {
  description = "ARN of the root-level Workloads OU."
  value       = aws_organizations_organizational_unit.workloads.arn
}

output "workloads_ou_name" {
  description = "Name of the root-level Workloads OU."
  value       = aws_organizations_organizational_unit.workloads.name
}

output "workloads_control_tower_baseline_arn" {
  description = "ARN of the enabled AWSControlTowerBaseline for the Workloads OU."
  value       = aws_controltower_baseline.workloads.arn
}

output "environment_ou_ids" {
  description = "Organizations IDs of the environment OUs, keyed by environment."
  value       = { for key, ou in aws_organizations_organizational_unit.environment : key => ou.id }
}

output "environment_ou_arns" {
  description = "ARNs of the environment OUs, keyed by environment."
  value       = { for key, ou in aws_organizations_organizational_unit.environment : key => ou.arn }
}

output "environment_ou_names" {
  description = "Names of the environment OUs, keyed by environment."
  value       = { for key, ou in aws_organizations_organizational_unit.environment : key => ou.name }
}

output "environment_control_tower_baseline_arns" {
  description = "ARNs of the enabled AWSControlTowerBaselines, keyed by environment."
  value       = { for key, baseline in aws_controltower_baseline.environment : key => baseline.arn }
}
