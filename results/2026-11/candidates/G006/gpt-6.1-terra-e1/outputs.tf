output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Storage account Azure resource ID."
  value       = azurerm_storage_account.app.id
}

output "blob_endpoint" {
  description = "Blob service URL for use with an Azure identity credential."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Private application blob container name."
  value       = azurerm_storage_container.app.name
}

output "container_url" {
  description = "URL of the private application blob container."
  value       = "${azurerm_storage_account.app.primary_blob_endpoint}${azurerm_storage_container.app.name}"
}
