output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account (globally unique)."
  value       = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  description = "Primary blob endpoint. Apps connect with their managed identity (DefaultAzureCredential), not keys."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of container name to container URL."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}"
  }
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = data.azurerm_resource_group.app.name
}
