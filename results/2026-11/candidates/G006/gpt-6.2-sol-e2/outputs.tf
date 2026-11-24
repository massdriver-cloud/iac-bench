output "storage_account_name" {
  description = "Name of the application's storage account."
  value       = azurerm_storage_account.application.name
}

output "storage_account_id" {
  description = "ARM resource ID of the application's storage account."
  value       = azurerm_storage_account.application.id
}

output "blob_endpoint" {
  description = "Blob service URL to use with an Azure SDK and the application's Entra credential. This same URL is used with private DNS when private access is configured."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "container_urls" {
  description = "Map from container name to its Blob Storage URL. These URLs do not include credentials."
  value = {
    for name in sort(tolist(var.container_names)) : name => "${trimsuffix(azurerm_storage_account.application.primary_blob_endpoint, "/")}/${name}"
  }
}
