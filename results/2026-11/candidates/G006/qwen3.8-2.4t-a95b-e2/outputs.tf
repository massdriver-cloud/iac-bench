output "storage_account_name" {
  description = "Name of the storage account, e.g. \"stordersstaging\". Use this in application configuration."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint, e.g. https://stordersstaging.blob.core.windows.net/."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "resource_group_name" {
  description = "Resource group the storage account was placed in."
  value       = azurerm_storage_account.this.resource_group_name
}

output "blob_containers" {
  description = "Map of the containers created, keyed by container name."
  value       = { for name, c in azurerm_storage_container.this : name => c.name }
}
