output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Generated (globally unique) name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint — use this with Azure SDKs and DefaultAzureCredential / managed identity."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the private blob containers created for the application."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "container_ids" {
  description = "Resource IDs of the created containers, keyed by container name."
  value       = { for name, c in azurerm_storage_container.this : name => c.id }
}

output "resource_group_name" {
  description = "Resource group the storage account was placed in."
  value       = data.azurerm_resource_group.app.name
}

output "location" {
  description = "Azure region of the storage account (inherited from the app's resource group)."
  value       = azurerm_storage_account.this.location
}
