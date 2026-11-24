output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.app.name
}

output "storage_account_id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.app.id
}

output "blob_endpoint" {
  description = "Blob service endpoint; use Entra ID authentication."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "container_name" {
  description = "Private application blob container."
  value       = azurerm_storage_container.app.name
}

output "private_endpoint_id" {
  description = "Blob private endpoint ID, if enabled."
  value       = try(azurerm_private_endpoint.blob[0].id, null)
}
