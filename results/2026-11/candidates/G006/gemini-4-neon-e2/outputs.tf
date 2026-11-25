output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary HTTPS Blob Storage endpoint URL for Azure SDK clients using Entra ID (DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Primary Blob Storage hostname (without scheme or trailing slash)."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "containers" {
  description = "Map of created blob containers with their ARM IDs and HTTPS URLs."
  value = {
    for name, container in azurerm_storage_container.this : name => {
      id       = container.id
      name     = container.name
      endpoint = "${azurerm_storage_account.this.primary_blob_endpoint}${container.name}"
    }
  }
}

output "replication_type" {
  description = "Effective Azure Storage replication type applied to the storage account."
  value       = azurerm_storage_account.this.account_replication_type
}

output "private_endpoint_id" {
  description = "Azure Resource ID of the Blob Private Endpoint, or null if not enabled."
  value       = try(azurerm_private_endpoint.blob[0].id, null)
}

output "private_endpoint_ip_address" {
  description = "Private IP address assigned to the Blob Private Endpoint, or null if not enabled."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, null)
}

output "app_env_vars" {
  description = "Non-secret environment variables ready to inject into AKS Deployments or App Service App Settings (authenticate with DefaultAzureCredential)."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
  }
}
