output "storage_account_id" {
  description = "Resource ID of the application's storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Storage account name; not a credential."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS blob endpoint for Azure SDK clients using Entra authentication."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "container_urls" {
  description = "Container URLs keyed by name; authentication is required for every request."
  value = {
    for name, container in azurerm_storage_container.application :
    name => "${azurerm_storage_account.application.primary_blob_endpoint}${container.name}"
  }
}
