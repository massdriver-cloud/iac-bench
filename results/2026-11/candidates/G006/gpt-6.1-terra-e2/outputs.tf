output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Storage account Azure resource ID."
  value       = azurerm_storage_account.app.id
}

output "blob_endpoint" {
  description = "Blob service endpoint for Azure SDK clients."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Default private container for application blobs."
  value       = azurerm_storage_container.app.name
}

output "container_url" {
  description = "URL of the default application container."
  value       = "${azurerm_storage_account.app.primary_blob_endpoint}${azurerm_storage_container.app.name}"
}
