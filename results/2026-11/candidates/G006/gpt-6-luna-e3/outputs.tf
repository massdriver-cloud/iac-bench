output "storage_account_id" {
  description = "Resource ID of the application storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Name of the application storage account."
  value       = azurerm_storage_account.application.name
}

output "primary_blob_endpoint" {
  description = "HTTPS endpoint for the storage account's Blob service."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "container_name" {
  description = "Name of the private application data container."
  value       = azurerm_storage_container.application.name
}
