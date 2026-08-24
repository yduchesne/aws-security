# budgets.tf

resource "aws_budgets_budget" "monthly_account_budget" {
  account_id = data.aws_caller_identity.current.account_id

  name         = "management-account-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Early warning when AWS forecasts that the budget will be exceeded.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }

  # Warning when actual spend reaches 80%.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  # Warning when actual spend exceeds the monthly budget.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  lifecycle {
    precondition {
      condition     = length(var.budget_notification_emails) > 0
      error_message = "At least one budget notification email address must be configured."
    }
  }
}
