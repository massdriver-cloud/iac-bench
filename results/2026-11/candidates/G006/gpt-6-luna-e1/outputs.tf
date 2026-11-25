output "storage_account_id" {
  description = "Resource ID of the application's storage account."
  value       = azurerm_storage_account.app.id
}

output "storage_account_name" {
  description = "Generated globally unique storage account name."
  value       = azurerm_storage_account.app.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint for the storage account."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "application_role_assignment_id" {
  description = "ID of the application's Storage Blob Data Contributor assignment."
  value       = azurerm_role_assignment.application_blob_data.id
}
