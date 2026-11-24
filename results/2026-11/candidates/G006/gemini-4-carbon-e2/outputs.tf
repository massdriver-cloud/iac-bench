output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Globally unique name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary HTTPS Blob service endpoint URL (pass to Azure Storage SDKs alongside DefaultAzureCredential)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Hostname of the primary Blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "containers" {
  description = "Map of created blob containers with their resource ID, name, and full HTTPS URL."
  value = {
    for name, container in azurerm_storage_container.this : name => {
      id   = container.id
      name = container.name
      url  = "${trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")}/${container.name}"
    }
  }
}

output "app_settings" {
  description = "Ready-to-merge environment variables for Azure App Service app_settings or AKS Kubernetes ConfigMaps."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
  }
}

output "private_endpoint_id" {
  description = "Resource ID of the Blob Private Endpoint when private_endpoint_subnet_id is provided, or null otherwise."
  value       = try(azurerm_private_endpoint.blob[0].id, null)
}

output "private_endpoint_ip_address" {
  description = "Private IPv4 address assigned to the Blob Private Endpoint when enabled, or null otherwise."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, null)
}
