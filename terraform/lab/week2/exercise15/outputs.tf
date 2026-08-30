output "role_arn" {
  description = "ARN of the working-path source caller role."
  value       = aws_iam_role.caller.arn
}

output "caller_role_arn" {
  description = "ARN of the working-path source caller role."
  value       = aws_iam_role.caller.arn
}

output "caller_without_assume_role_arn" {
  description = "ARN of the Failure A source role without sts:AssumeRole permission."
  value       = aws_iam_role.caller_without_assume.arn
}

output "untrusted_caller_role_arn" {
  description = "ARN of the Failure B source role absent from target trust policies."
  value       = aws_iam_role.untrusted_caller.arn
}

output "target_role_arn" {
  description = "ARN of the working-path target role."
  value       = aws_iam_role.target.arn
}

output "target_external_id_role_arn" {
  description = "ARN of the Failure D target role requiring an ExternalId."
  value       = aws_iam_role.target_external_id.arn
}

output "target_condition_role_arn" {
  description = "ARN of the Failure E target role with a mismatched trust condition."
  value       = aws_iam_role.target_condition.arn
}

output "external_id" {
  description = "ExternalId identifier configured for the Failure D fixture."
  value       = var.external_id
}

output "scp_policy_arn" {
  description = "ARN of the optional Exercise 15 SCP, or null when disabled."
  value       = one(aws_organizations_policy.exercise_scp_deny[*].arn)
}

output "scp_deny_enabled" {
  description = "Whether the Exercise 15 SCP deny is enabled."
  value       = var.scp_deny_enabled
}
