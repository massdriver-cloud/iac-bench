output "storage_account_id" {
  description = "Resource ID of the created Azure Storage Account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Generated globally unique name of the Azure Storage Account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary Blob service endpoint URL for the application (use with Entra ID / DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "List of private blob container names created in the storage account."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_ids" {
  description = "Map of container name to Azure Resource Manager ID."
  value       = { for name, c in azurerm_storage_container.this : name => c.id }
}

output "private_endpoint_id" {
  description = "Resource ID of the Blob Private Endpoint, if created."
  value       = try(azurerm_private_endpoint.blob[0].id, null)
}
