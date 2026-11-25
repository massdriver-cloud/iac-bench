output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Globally unique name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group in which the storage account and related resources are deployed."
  value       = azurerm_storage_account.this.resource_group_name
}

output "location" {
  description = "Azure region in which the storage account is deployed."
  value       = azurerm_storage_account.this.location
}

output "blob_endpoint" {
  description = "Primary HTTPS Blob service endpoint URL (pass directly to Azure SDK BlobServiceClient with DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "blob_host" {
  description = "Primary Blob service hostname without scheme."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "containers" {
  description = "Map of provisioned blob containers keyed by container name, including each container's ARM ID and HTTPS URL."
  value = {
    for name, c in azurerm_storage_container.this : name => {
      id   = c.id
      name = c.name
      url  = c.url
    }
  }
}

output "container_names" {
  description = "Sorted list of blob container names provisioned in the storage account."
  value       = sort(keys(azurerm_storage_container.this))
}

output "app_configuration" {
  description = "Ready-to-use environment variables / App Service settings map for AKS ConfigMaps or App Service app_settings."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
  }
}

output "private_endpoint_id" {
  description = "Resource ID of the Blob Private Endpoint when private_endpoint_subnet_id is set, or null otherwise."
  value       = try(azurerm_private_endpoint.blob[0].id, null)
}

output "private_endpoint_ip" {
  description = "Private IPv4 address allocated to the Blob Private Endpoint when private_endpoint_subnet_id is set, or null otherwise."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, null)
}
