output "storage_account_name" {
  description = "Globally unique name of the storage account."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = azurerm_storage_account.app.id
}

output "blob_endpoint" {
  description = "Blob service URL for Azure SDK clients. Private DNS resolves this hostname to the private endpoint inside the application network."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_urls" {
  description = "Blob container URLs keyed by container name. These contain no credentials."
  value = {
    for name in keys(azurerm_storage_container.app) : name => "${trimsuffix(azurerm_storage_account.app.primary_blob_endpoint, "/")}/${name}"
  }
}
