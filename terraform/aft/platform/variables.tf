variable "management_account_id" {
  description = "AWS Control Tower / Organizations management account ID."
  type        = string
}

variable "aft_management_account_id" {
  description = "Dedicated AFT management account ID created by bootstrap."
  type        = string
}

variable "audit_account_id" {
  description = "Control Tower Audit/Security Tooling account ID."
  type        = string
}

variable "log_archive_account_id" {
  description = "Control Tower Log Archive account ID."
  type        = string
}

variable "home_region" {
  description = "AWS Control Tower home Region."
  type        = string
  default     = "us-east-2"
}

variable "vcs_provider" {
  description = "AFT VCS provider: github, bitbucket, githubenterprise, gitlab, or another AFT-supported provider."
  type        = string
  default     = "github"
}

variable "account_request_repo_name" {
  description = "AFT account request repository. For non-CodeCommit VCS, use Org/Repo format."
  type        = string
}

variable "global_customizations_repo_name" {
  description = "AFT global customizations repository. For non-CodeCommit VCS, use Org/Repo format."
  type        = string
}

variable "account_customizations_repo_name" {
  description = "AFT account customizations repository. For non-CodeCommit VCS, use Org/Repo format."
  type        = string
}

variable "account_provisioning_customizations_repo_name" {
  description = "AFT account provisioning customizations repository. For non-CodeCommit VCS, use Org/Repo format."
  type        = string
}

variable "repository_branch" {
  description = "Default branch used by the AFT repositories."
  type        = string
  default     = "main"
}

variable "aft_enable_vpc" {
  description = "Whether AFT deploys its default VPC. This architecture disables it to avoid NAT gateway and interface endpoint costs."
  type        = bool
  default     = false

  validation {
    condition     = var.aft_enable_vpc == false
    error_message = "aft_enable_vpc must remain false for this architecture. Review docs/aft-setup.md and the networking and cost tradeoffs before changing this invariant."
  }
}

variable "aft_metrics_reporting" {
  description = "Whether AFT sends anonymous operational metrics to AWS."
  type        = bool
  default     = true
}

variable "aft_feature_delete_default_vpcs_enabled" {
  description = "Whether AFT removes default VPCs from accounts it provisions."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Tags applied to supported AFT resources."
  type        = map(string)

  default = {
    Project   = "aws-security-landing-zone"
    ManagedBy = "Terraform"
    Phase     = "aft"
  }
}
