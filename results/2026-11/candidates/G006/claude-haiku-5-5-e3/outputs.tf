output "resource_group_name" {
  description = "Resource group the storage account was created in."
  value       = data.azurerm_resource_group.app.name
}

output "storage_account_name" {
  description = "Name of the storage account. Use it as the account name in SDK endpoints."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Primary blob service endpoint. Authenticate with the application's Entra ID identity; no keys are issued."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Names of the containers created for this workload."
  value       = sort(keys(azurerm_storage_container.this))
}
