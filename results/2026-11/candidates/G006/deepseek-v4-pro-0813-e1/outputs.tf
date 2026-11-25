output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint for the storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of container names to container resource IDs."
  value = {
    for name, container in azurerm_storage_container.this :
    name => container.id
  }
}
