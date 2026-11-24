output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account. SDK clients usually only need the blob endpoint."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group the storage account was placed in."
  value       = azurerm_storage_account.this.resource_group_name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint. Point SDK clients here and authenticate with the application's Entra ID identity (e.g. DefaultAzureCredential in the Azure SDKs) - there are no connection strings or account keys."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of blob container name => container resource ID."
  value       = { for name, container in azurerm_storage_container.this : name => container.id }
}
