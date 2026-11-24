output "storage_account_id" {
  description = "The Resource Manager ID of the storage account."
  value       = azurerm_storage_account.storage.id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.storage.name
}

output "primary_blob_endpoint" {
  description = "The primary blob service endpoint URL. Use this for Azure SDK clients with Entra ID authentication (DefaultAzureCredential)."
  value       = azurerm_storage_account.storage.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "The primary blob service host name."
  value       = azurerm_storage_account.storage.primary_blob_host
}

output "resource_group_name" {
  description = "The name of the resource group containing the storage account."
  value       = data.azurerm_resource_group.rg.name
}

output "location" {
  description = "The Azure region where the storage account is deployed."
  value       = local.location
}

output "containers" {
  description = "Map of created containers with their IDs, names, and access URLs."
  value = {
    for name, c in azurerm_storage_container.containers : name => {
      id   = c.id
      name = c.name
      url  = "${azurerm_storage_account.storage.primary_blob_endpoint}${c.name}"
    }
  }
}

output "container_names" {
  description = "List of container names created in this storage account."
  value       = [for c in azurerm_storage_container.containers : c.name]
}

output "assigned_role_principals" {
  description = "List of Entra ID principal IDs granted the application role."
  value       = local.app_principal_ids
}

output "primary_access_key" {
  description = "The primary shared access key for the storage account. Marked sensitive."
  value       = azurerm_storage_account.storage.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "The primary connection string for the storage account. Marked sensitive."
  value       = azurerm_storage_account.storage.primary_connection_string
  sensitive   = true
}
