output "id" {
  value       = azurerm_storage_account.this.id
  description = "The ID of the storage account."
}

output "name" {
  value       = azurerm_storage_account.this.name
  description = "The name of the storage account."
}

output "primary_blob_endpoint" {
  value       = azurerm_storage_account.this.primary_blob_endpoint
  description = "The endpoint URL for blob storage in the primary location."
}

output "primary_blob_host" {
  value       = azurerm_storage_account.this.primary_blob_host
  description = "The hostname for blob storage in the primary location."
}

output "primary_access_key" {
  value       = azurerm_storage_account.this.primary_access_key
  description = "The primary access key for the storage account."
  sensitive   = true
}

output "secondary_access_key" {
  value       = azurerm_storage_account.this.secondary_access_key
  description = "The secondary access key for the storage account."
  sensitive   = true
}

output "primary_connection_string" {
  value       = azurerm_storage_account.this.primary_connection_string
  description = "The connection string associated with the primary location."
  sensitive   = true
}

output "secondary_connection_string" {
  value       = azurerm_storage_account.this.secondary_connection_string
  description = "The connection string associated with the secondary location."
  sensitive   = true
}

output "containers" {
  value = {
    for k, v in azurerm_storage_container.this : k => {
      id   = v.id
      name = v.name
    }
  }
  description = "Map of created blob containers and their properties."
}

output "role_assignments" {
  value = merge(
    {
      for k, v in azurerm_role_assignment.principals : k => {
        id                   = v.id
        principal_id         = v.principal_id
        role_definition_name = v.role_definition_name
      }
    },
    {
      for k, v in azurerm_role_assignment.custom : k => {
        id                   = v.id
        principal_id         = v.principal_id
        role_definition_name = v.role_definition_name
      }
    }
  )
  description = "Map of role assignments created for the storage account."
}
