output "storage_account_name" {
  description = "Name of the application storage account."
  value       = azurerm_storage_account.app.name
}

output "blob_service_url" {
  description = "HTTPS service endpoint for the Azure Blob SDK."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Private blob container for application objects."
  value       = azurerm_storage_container.files.name
}
