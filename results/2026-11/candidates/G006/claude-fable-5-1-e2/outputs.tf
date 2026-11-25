output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account. Applications use this with DefaultAzureCredential - no keys or connection strings."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = data.azurerm_resource_group.app.name
}

output "location" {
  description = "Azure region of the storage account (inherited from the resource group)."
  value       = data.azurerm_resource_group.app.location
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint, e.g. https://<account>.blob.core.windows.net/. Point the application's blob client at this URL."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the containers created in the account."
  value       = sort([for c in azurerm_storage_container.this : c.name])
}

output "container_urls" {
  description = "Map of container name to its full blob URL."
  value       = { for name, c in azurerm_storage_container.this : name => "${azurerm_storage_account.this.primary_blob_endpoint}${name}" }
}

output "replication_type" {
  description = "Redundancy chosen for this environment."
  value       = azurerm_storage_account.this.account_replication_type
}
