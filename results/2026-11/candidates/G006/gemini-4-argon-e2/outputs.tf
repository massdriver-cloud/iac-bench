output "storage_account_id" {
  description = "The Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "The name of the storage account (pass to Azure SDK DefaultAzureCredential configurations)."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "The resource group containing the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}

output "primary_blob_endpoint" {
  description = "The primary HTTPS Blob service endpoint URL (e.g., 'https://<account>.blob.core.windows.net/') for the application's Azure Blob Storage SDK client."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "The hostname of the primary Blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "container_names" {
  description = "List of blob container names created in the storage account."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_ids" {
  description = "Map of container name to Azure Resource Manager container ID."
  value       = { for k, v in azurerm_storage_container.this : k => v.id }
}

output "container_urls" {
  description = "Map of container name to its full HTTPS blob container URL."
  value = {
    for k, v in azurerm_storage_container.this :
    k => "${trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")}/${k}"
  }
}

output "app_configuration_settings" {
  description = "Ready-to-use environment variables for AKS ConfigMaps or App Service app_settings using Entra ID authentication."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
  }
}
