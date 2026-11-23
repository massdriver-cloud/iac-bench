output "id" {
  description = "Storage account ID."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
