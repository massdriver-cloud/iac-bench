output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service endpoint URL applications should connect to (authenticate with Entra ID; shared keys are disabled)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the created containers."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = data.azurerm_resource_group.app.name
}
