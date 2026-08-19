output "account_factory_provisioned_product_id" {
  description = "Service Catalog provisioned-product ID for the AFT management account request."
  value       = aws_servicecatalog_provisioned_product.aft_management.id
}

output "account_factory_provisioned_product_arn" {
  description = "Service Catalog provisioned-product ARN for the AFT management account request."
  value       = aws_servicecatalog_provisioned_product.aft_management.arn
}

output "account_factory_status" {
  description = "Current Account Factory provisioned-product status."
  value       = aws_servicecatalog_provisioned_product.aft_management.status
}

locals {
  account_factory_outputs = {
    for output in aws_servicecatalog_provisioned_product.aft_management.outputs :
    output.key => output.value
  }
}

output "account_factory_outputs" {
  description = "Outputs returned by the Control Tower Account Factory product."
  value       = local.account_factory_outputs
}

output "aft_management_account_id" {
  description = "AFT management account ID returned by Account Factory; verify this is non-null before deploying the platform root."
  value       = try(local.account_factory_outputs["AccountId"], null)
}
