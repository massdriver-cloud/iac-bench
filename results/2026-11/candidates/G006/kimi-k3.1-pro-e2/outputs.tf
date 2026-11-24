output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "HTTPS blob endpoint for application configuration."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the private containers managed by the module."
  value       = sort(tolist(var.containers))
}

output "container_ids" {
  description = "Map of container names to their Azure resource IDs."
  value       = { for name, container in azapi_resource.container : name => container.id }
}

output "application_principal_id" {
  description = "Principal ID that received Storage Blob Data Contributor access."
  value       = var.application_principal_id
}
