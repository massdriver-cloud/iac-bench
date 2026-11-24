output "storage_account_id" {
  description = "Resource ID of the application's storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Account name for application configuration."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS Blob service URL. Use an Azure SDK with an Entra token credential, not an account key."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "containers" {
  description = "Container names mapped to their Azure resource IDs."
  value       = { for name, container in azurerm_storage_container.application : name => container.resource_manager_id }
}
