output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service endpoint. Use with DefaultAzureCredential / managed identity — account keys are disabled."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of container name to container URL."
  value       = { for k, c in azurerm_storage_container.this : k => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}" }
}
