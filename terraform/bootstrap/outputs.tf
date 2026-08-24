output "organization_id" {
  description = "AWS Organizations organization ID."
  value       = aws_organizations_organization.main.id
}

output "organization_root_id" {
  description = "AWS Organizations root ID."
  value       = aws_organizations_organization.main.roots[0].id
}

output "security_ou_id" {
  description = "Security OU ID."
  value       = aws_organizations_organizational_unit.security.id
}

output "security_tooling_account_id" {
  description = "Security Tooling AWS account ID."
  value       = aws_organizations_account.security_tooling.id
}

output "log_archive_account_id" {
  description = "Log Archive AWS account ID."
  value       = aws_organizations_account.log_archive.id
}

output "landing_zone_arn" {
  description = "Control Tower landing zone ARN."
  value       = aws_controltower_landing_zone.main.arn
}

output "landing_zone_drift_status" {
  description = "Control Tower's drift status for the landing zone."
  value       = try(aws_controltower_landing_zone.main.drift_status[0].status, null)
}

output "landing_zone_latest_available_version" {
  description = "Latest Control Tower landing-zone version reported by AWS."
  value       = aws_controltower_landing_zone.main.latest_available_version
}
