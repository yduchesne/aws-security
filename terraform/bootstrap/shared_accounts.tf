# Creating the Security Tooling and Log Archive accounts.
# Those are mandated as prerequisites by Control Tower.
#
# Note on 'close_on_deletion' set to false: we are being conservative regarding
# account deletion. We don't want to delete accounts automatically upon tf destroy.

resource "aws_organizations_account" "security_tooling" {
  name      = "Security Tooling"
  email     = var.security_tooling_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  tags = {
    Purpose = "Centralized security tooling"
  }
}

resource "aws_organizations_account" "log_archive" {
  name      = "Log Archive"
  email     = var.log_archive_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  tags = {
    Purpose = "Centralized logging"
  }
}
