output "approved_role_arn" {
  description = "ARN of the source role retained by the hardened target trust policy."
  value       = aws_iam_role.approved.arn
}

output "unapproved_role_arn" {
  description = "ARN of the source role removed from the hardened target trust policy."
  value       = aws_iam_role.unapproved.arn
}

output "target_role_arn" {
  description = "ARN of the target role used in both trust-policy phases."
  value       = aws_iam_role.target.arn
}

output "trust_mode" {
  description = "Trust mode currently represented by the Terraform state."
  value       = var.trust_mode
}
