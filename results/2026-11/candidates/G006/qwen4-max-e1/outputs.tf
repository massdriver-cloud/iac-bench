output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint. Use with Entra ID auth (DefaultAzureCredential / managed identity), not account keys - keys are disabled."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the private blob containers created for the application."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "container_ids" {
  description = "Map of container name to resource ID."
  value       = { for k, c in azurerm_storage_container.this : k => c.id }
}

output "resource_group_name" {
  description = "Resource group the storage account lives in (the application's existing group)."
  value       = var.resource_group_name
}

output "location" {
  description = "Azure region of the storage account."
  value       = azurerm_storage_account.this.location
}
