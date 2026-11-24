output "storage_account_name" {
  description = "Generated Azure Storage account name."
  value       = azurerm_storage_account.app.name
}

output "blob_service_endpoint" {
  description = "Account URL for the Azure Blob SDK; authenticate using the application's identity."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Private blob container for application files."
  value       = azurerm_storage_container.files.name
}
