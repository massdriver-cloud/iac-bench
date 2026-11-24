output "storage_account_name" {
  description = "Name of the storage account (configure this in the application)."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service endpoint the application should use with its Entra ID identity."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the blob containers created."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "resource_group_name" {
  description = "Resource group containing the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}
