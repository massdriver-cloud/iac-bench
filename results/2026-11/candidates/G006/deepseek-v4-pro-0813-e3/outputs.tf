output "storage_account_id" {
  description = "Resource ID of the storage account. Use this in role assignments and as a data source reference."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint URL for the storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_connection_string" {
  description = "Primary connection string. Empty when shared access keys are disabled (the default)."
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
}

output "container_names" {
  description = "Names of the blob containers created by this module."
  value       = keys(azurerm_storage_container.this)
}

output "container_ids" {
  description = "Map of container name to container resource ID."
  value = {
    for name, container in azurerm_storage_container.this : name => container.id
  }
}
