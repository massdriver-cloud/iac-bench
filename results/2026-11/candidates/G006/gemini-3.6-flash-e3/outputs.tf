output "storage_account_id" {
  value       = azurerm_storage_account.this.id
  description = "The ID of the Storage Account."
}

output "storage_account_name" {
  value       = azurerm_storage_account.this.name
  description = "The name of the Storage Account."
}

output "storage_account_primary_location" {
  value       = azurerm_storage_account.this.primary_location
  description = "The primary location of the Storage Account."
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

output "secondary_access_key" {
  value       = azurerm_storage_account.this.secondary_access_key
  sensitive   = true
  description = "The secondary access key for the storage account."
}

output "primary_connection_string" {
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
  description = "The connection string associated with the primary location."
}

output "secondary_connection_string" {
  value       = azurerm_storage_account.this.secondary_connection_string
  sensitive   = true
  description = "The connection string associated with the secondary location."
}

output "containers" {
  value = {
    for k, v in azurerm_storage_container.containers : k => {
      id   = v.id
      name = v.name
    }
  }
  description = "Map of created blob containers."
}

output "queues" {
  value = {
    for k, v in azurerm_storage_queue.queues : k => {
      id   = v.id
      name = v.name
    }
  }
  description = "Map of created queues."
}

output "tables" {
  value = {
    for k, v in azurerm_storage_table.tables : k => {
      id   = v.id
      name = v.name
    }
  }
  description = "Map of created tables."
}

output "file_shares" {
  value = {
    for k, v in azurerm_storage_share.shares : k => {
      id    = v.id
      name  = v.name
      quota = v.quota
    }
  }
  description = "Map of created file shares."
}
