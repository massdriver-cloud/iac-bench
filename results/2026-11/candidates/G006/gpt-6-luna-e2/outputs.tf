output "storage_account_name" {
  description = "Generated globally unique name of the storage account."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.app.id
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint for the application to use with Entra ID authentication."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}
