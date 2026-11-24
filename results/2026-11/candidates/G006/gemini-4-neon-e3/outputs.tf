output "storage_account_id" {
  value       = azurerm_storage_account.this.id
  description = "Azure Resource Manager ID of the storage account."
}

output "storage_account_name" {
  value       = azurerm_storage_account.this.name
  description = "Generated globally unique name of the storage account."
}

output "primary_blob_endpoint" {
  value       = azurerm_storage_account.this.primary_blob_endpoint
  description = "HTTPS endpoint URL for the Blob service. Pass this directly to Azure Blob Storage SDKs alongside DefaultAzureCredential."
}

output "primary_blob_host" {
  value       = azurerm_storage_account.this.primary_blob_host
  description = "Hostname of the Blob service endpoint (without scheme)."
}

output "container_names" {
  value       = sort(keys(azurerm_storage_container.this))
  description = "Sorted list of private blob container names created in the storage account."
}

output "container_urls" {
  value = {
    for name, container in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${container.name}"
  }
  description = "Map of container name to its full HTTPS blob container URL."
}

output "replication_type" {
  value       = azurerm_storage_account.this.account_replication_type
  description = "Effective storage redundancy tier selected for this environment (LRS, GRS, ZRS, or GZRS)."
}

output "private_endpoint_ip_address" {
  value       = local.use_private_endpoint ? azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address : null
  description = "Private IP address of the blob Private Endpoint, or null if Private Endpoint is not enabled."
}
