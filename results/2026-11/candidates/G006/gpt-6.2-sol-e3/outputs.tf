output "storage_account_name" {
  description = "Name of the Azure storage account."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.app.id
}

output "blob_endpoint" {
  description = "Blob service URL for use with an Entra-authenticated Azure SDK client."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_urls" {
  description = "Blob container URLs keyed by name. These URLs grant no access on their own."
  value = {
    for name, container in azurerm_storage_container.app : name => "${trimsuffix(azurerm_storage_account.app.primary_blob_endpoint, "/")}/${container.name}"
  }
}
