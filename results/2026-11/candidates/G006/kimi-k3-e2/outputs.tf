output "id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob endpoint the application talks to, e.g. \"https://stordersprod01.blob.core.windows.net/\"."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of container name to container resource ID, for every container created via `containers`."
  value       = { for name, container in azurerm_storage_container.this : name => container.id }
}
