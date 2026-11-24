output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Globally unique name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary HTTPS blob endpoint URL for use with Azure SDKs and Entra ID credentials (e.g., DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "resource_group_name" {
  description = "Resource group containing the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}

output "location" {
  description = "Azure region where the storage account is deployed."
  value       = azurerm_storage_account.this.location
}

output "containers" {
  description = "Map of created blob containers keyed by container name, with their resource IDs."
  value = {
    for name, container in azurerm_storage_container.this : name => {
      id   = container.id
      name = container.name
    }
  }
}

output "private_endpoint_ip_address" {
  description = "Private IP address of the blob Private Endpoint, if created."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, null)
}
