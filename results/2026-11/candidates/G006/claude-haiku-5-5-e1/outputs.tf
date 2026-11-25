output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  description = "Primary blob service endpoint. Applications connect with Entra ID (managed identity), not keys."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Names of the private blob containers created for the application."
  value       = sort([for c in azurerm_storage_container.this : c.name])
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = data.azurerm_resource_group.app.name
}
