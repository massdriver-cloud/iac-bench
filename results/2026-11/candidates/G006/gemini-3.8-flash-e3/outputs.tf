output "storage_account_id" {
  description = "The ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "The name of the resource group hosting the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}

output "location" {
  description = "The Azure region where the storage account is deployed."
  value       = azurerm_storage_account.this.location
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint URL (e.g. 'https://<account>.blob.core.windows.net/'). Use this in AKS and App Service configuration."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "The primary blob endpoint hostname."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "primary_dfs_endpoint" {
  description = "The primary Data Lake / DFS endpoint URL."
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "primary_web_endpoint" {
  description = "The primary web endpoint URL."
  value       = azurerm_storage_account.this.primary_web_endpoint
}

output "container_names" {
  description = "List of blob container names created in this storage account."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "containers" {
  description = "Map of container names to container IDs."
  value       = { for name, c in azurerm_storage_container.this : name => c.id }
}

output "replication_type" {
  description = "The storage replication type configured (e.g., ZRS or LRS)."
  value       = azurerm_storage_account.this.account_replication_type
}

output "role_assignment_ids" {
  description = "Map of principal IDs to role assignment IDs."
  value       = { for k, v in azurerm_role_assignment.blob_contributor : k => v.id }
}

output "primary_access_key" {
  description = "The primary access key for the storage account (sensitive)."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "The primary connection string for the storage account (sensitive)."
  value       = azurerm_storage_account.this.primary_blob_connection_string
  sensitive   = true
}
