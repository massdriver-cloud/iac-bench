output "account_name" {
  description = "Globally unique name of the storage account, e.g. \"stordersstagingk7d2\". Use this in app settings."
  value       = azurerm_storage_account.this.name
}

output "account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "resource_group_name" {
  description = "Resource group the storage account lives in (the application's)."
  value       = local.resource_group_name
}

output "location" {
  description = "Azure region of the storage account."
  value       = azurerm_storage_account.this.location
}

output "blob_endpoint" {
  description = "Blob service endpoint, e.g. https://stordersstagingk7d2.blob.core.windows.net/. Authenticate with the app identity."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "queue_endpoint" {
  description = "Queue service endpoint (relevant when `queues` is set)."
  value       = azurerm_storage_account.this.primary_queue_endpoint
}

output "file_endpoint" {
  description = "Files service endpoint (relevant when `file_shares` is set)."
  value       = azurerm_storage_account.this.primary_file_endpoint
}
