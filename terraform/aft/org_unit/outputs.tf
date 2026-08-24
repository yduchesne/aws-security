output "landing_zone_arn" {
  description = "Existing landing-zone ARN used as this root's prerequisite."
  value       = var.landing_zone_arn
}

output "aft_ou_id" {
  description = "Organizations ID of the dedicated AFT OU."
  value       = aws_organizations_organizational_unit.aft.id
}

output "aft_ou_arn" {
  description = "ARN of the dedicated AFT OU."
  value       = aws_organizations_organizational_unit.aft.arn
}

output "aft_ou_name" {
  description = "Name of the dedicated AFT OU."
  value       = aws_organizations_organizational_unit.aft.name
}

output "aft_control_tower_baseline_arn" {
  description = "ARN of the enabled AWSControlTowerBaseline for the AFT OU."
  value       = aws_controltower_baseline.aft.arn
}
