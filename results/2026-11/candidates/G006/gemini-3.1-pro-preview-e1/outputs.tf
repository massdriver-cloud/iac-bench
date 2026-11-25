output "storage_account_id" {
  description = "The ID of the storage account."
  value       = azurerm_storage_account.app_storage.id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.app_storage.name
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint of the storage account."
  value       = azurerm_storage_account.app_storage.primary_blob_endpoint
}

output "containers" {
  description = "A map of container names to their resource IDs."
  value       = { for k, v in azurerm_storage_container.app_containers : k => v.id }
}
