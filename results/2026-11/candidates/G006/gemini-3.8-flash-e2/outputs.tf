output "storage_account_id" {
  description = "The Resource Manager ID of the storage account."
  value       = azurerm_storage_account.storage.id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.storage.name
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint URL. Used by applications with Azure SDK (DefaultAzureCredential) to connect to blob storage."
  value       = azurerm_storage_account.storage.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "The primary blob endpoint hostname."
  value       = azurerm_storage_account.storage.primary_blob_host
}

output "primary_connection_string" {
  description = "The primary connection string for the storage account."
  value       = azurerm_storage_account.storage.primary_connection_string
  sensitive   = true
}

output "primary_access_key" {
  description = "The primary access key for the storage account."
  value       = azurerm_storage_account.storage.primary_access_key
  sensitive   = true
}

output "resource_group_name" {
  description = "The resource group containing the storage account."
  value       = azurerm_storage_account.storage.resource_group_name
}

output "location" {
  description = "The Azure region of the storage account."
  value       = azurerm_storage_account.storage.location
}

output "containers" {
  description = "A map of created containers with their IDs and resource manager IDs."
  value = {
    for name, c in azurerm_storage_container.containers : name => {
      id                  = c.id
      name                = c.name
      resource_manager_id = c.resource_manager_id
    }
  }
}

output "container_names" {
  description = "List of container names created in the storage account."
  value       = [for c in azurerm_storage_container.containers : c.name]
}

output "role_assignment_ids" {
  description = "Map of principal IDs to role assignment IDs created for application data access."
  value = {
    for principal, assignment in azurerm_role_assignment.app : principal => assignment.id
  }
}

output "assigned_role" {
  description = "The Azure RBAC role definition name assigned to the application identities."
  value       = var.role_definition_name
}
