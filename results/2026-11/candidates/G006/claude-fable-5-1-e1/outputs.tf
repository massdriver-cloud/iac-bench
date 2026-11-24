output "storage_account_name" {
  description = "Name of the storage account. Use it in the application's configuration (e.g. for a BlobServiceClient with DefaultAzureCredential)."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = azurerm_storage_account.this.resource_group_name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint, e.g. https://<account>.blob.core.windows.net/."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the containers created for the application."
  value       = sort([for c in azurerm_storage_container.this : c.name])
}

output "container_urls" {
  description = "Map of container name to its full URL."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${name}"
  }
}
