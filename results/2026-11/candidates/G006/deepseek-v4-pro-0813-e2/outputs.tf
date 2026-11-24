output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group that contains the storage account."
  value       = local.resource_group_name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "storage_container_ids" {
  description = "Map of container name to Azure resource ID for each created blob container."
  value       = { for name, container in azurerm_storage_container.this : name => container.id }
}

output "role_assignment_id" {
  description = "Azure resource ID of the Storage Blob Data Contributor role assignment for the application identity."
  value       = azurerm_role_assignment.blob_data_contributor.id
}