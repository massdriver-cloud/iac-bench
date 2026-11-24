output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group containing the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}

output "primary_blob_endpoint" {
  description = "Primary Blob Storage endpoint URL for Azure SDK configuration in AKS and App Service applications."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Hostname of the primary Blob Storage endpoint."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "container_names" {
  description = "List of blob container names created in the storage account."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_urls" {
  description = "Map of container names to their full blob container endpoint URLs."
  value = {
    for name, container in azurerm_storage_container.this :
    name => "${trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")}/${container.name}"
  }
}

output "container_ids" {
  description = "Map of container names to their Azure Resource Manager resource IDs."
  value = {
    for name, container in azurerm_storage_container.this :
    name => container.id
  }
}
