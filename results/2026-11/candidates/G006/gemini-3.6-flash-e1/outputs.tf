output "storage_account_id" {
  value       = azurerm_storage_account.this.id
  description = "The ID of the storage account."
}

output "storage_account_name" {
  value       = azurerm_storage_account.this.name
  description = "The name of the storage account."
}

output "primary_location" {
  value       = azurerm_storage_account.this.location
  description = "The primary location of the storage account."
}

output "primary_blob_endpoint" {
  value       = azurerm_storage_account.this.primary_blob_endpoint
  description = "The endpoint URL for blob storage in the primary location."
}

output "primary_blob_host" {
  value       = azurerm_storage_account.this.primary_blob_host
  description = "The hostname for blob storage in the primary location."
}

output "primary_queue_endpoint" {
  value       = azurerm_storage_account.this.primary_queue_endpoint
  description = "The endpoint URL for queue storage in the primary location."
}

output "primary_table_endpoint" {
  value       = azurerm_storage_account.this.primary_table_endpoint
  description = "The endpoint URL for table storage in the primary location."
}

output "primary_file_endpoint" {
  value       = azurerm_storage_account.this.primary_file_endpoint
  description = "The endpoint URL for file storage in the primary location."
}

output "primary_access_key" {
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
  description = "The primary access key for the storage account."
}

output "primary_connection_string" {
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
  description = "The primary connection string for the storage account."
}

output "containers" {
  value       = { for k, v in azurerm_storage_container.this : k => v.id }
  description = "Map of container names to container IDs."
}

output "file_shares" {
  value       = { for k, v in azurerm_storage_share.this : k => v.id }
  description = "Map of file share names to file share IDs."
}

output "queues" {
  value       = { for k, v in azurerm_storage_queue.this : k => v.id }
  description = "Map of queue names to queue IDs."
}

output "tables" {
  value       = { for k, v in azurerm_storage_table.this : k => v.id }
  description = "Map of table names to table IDs."
}
