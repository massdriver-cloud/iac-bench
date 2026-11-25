output "storage_account_name" {
  description = "Name of the storage account. Give this (or blob_endpoint) to the application as configuration."
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

output "blob_endpoint" {
  description = "Blob service URL, e.g. https://<account>.blob.core.windows.net/. Use it with the application's identity (DefaultAzureCredential); there are no keys or connection strings."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the containers that were created."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_urls" {
  description = "URL of each container, keyed by container name."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${name}"
  }
}

output "private_endpoint_id" {
  description = "Resource ID of the blob private endpoint."
  value       = azurerm_private_endpoint.blob.id
}

output "private_endpoint_ip_address" {
  description = "Private IP address the blob endpoint resolves to inside the virtual network."
  value       = try(azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address, null)
}
