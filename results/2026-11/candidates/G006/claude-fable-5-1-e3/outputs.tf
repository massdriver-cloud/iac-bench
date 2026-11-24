output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service endpoint. Point your SDK at this URL (e.g. BlobServiceClient(account_url=blob_endpoint, credential=DefaultAzureCredential())) - there are no keys or connection strings."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the blob containers created for the application."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_urls" {
  description = "Map of container name to its full URL."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${name}"
  }
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = data.azurerm_resource_group.app.name
}

output "location" {
  description = "Azure region of the storage account."
  value       = azurerm_storage_account.this.location
}
