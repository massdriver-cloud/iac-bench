output "storage_account_id" {
  description = "ARM resource ID of the storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Storage account name for application configuration."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS Blob service endpoint. Authenticate with the application's Entra identity, not an account key."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "container_urls" {
  description = "Container names mapped to URLs. These are not public or signed URLs."
  value = {
    for name, container in azurerm_storage_container.application :
    name => "${azurerm_storage_account.application.primary_blob_endpoint}${container.name}"
  }
}
