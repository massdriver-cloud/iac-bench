output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service URL to configure in the application (authenticate with its Entra ID identity, e.g. DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_urls" {
  description = "URL of each container, by name."
  value       = { for k, c in azurerm_storage_container.this : k => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}" }
}

output "resource_group_name" {
  description = "Resource group the account was created in."
  value       = local.resource_group_name
}
