output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint. Configure this in the application together with its Entra identity (e.g. DefaultAzureCredential); no key or connection string is needed."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_ids" {
  description = "Map of container name to resource ID."
  value       = { for name, container in azapi_resource.container : name => container.id }
}

output "resource_group_name" {
  description = "Resource group the storage account was deployed into."
  value       = azurerm_storage_account.this.resource_group_name
}
