output "storage_account_id" {
  description = "The Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.app.id
}

output "storage_account_name" {
  description = "The globally unique name of the storage account."
  value       = azurerm_storage_account.app.name
}

output "resource_group_name" {
  description = "The name of the resource group containing the storage account."
  value       = azurerm_storage_account.app.resource_group_name
}

output "location" {
  description = "The Azure region where the storage account is deployed."
  value       = azurerm_storage_account.app.location
}

output "primary_blob_endpoint" {
  description = "The primary HTTPS endpoint URL for Azure Blob Storage (pass this to the Azure Blob SDK with DefaultAzureCredential)."
  value       = azurerm_storage_account.app.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "The hostname of the primary blob endpoint."
  value       = azurerm_storage_account.app.primary_blob_host
}

output "containers" {
  description = "Map of container names to their full blob container URLs and resource IDs."
  value = {
    for name, container in azurerm_storage_container.app : name => {
      id   = container.id
      name = container.name
      url  = "${trimsuffix(azurerm_storage_account.app.primary_blob_endpoint, "/")}/${container.name}"
    }
  }
}

output "app_config" {
  description = "Ready-to-use environment variables / configuration settings for AKS ConfigMaps or App Service App Settings."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.app.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.app.primary_blob_endpoint
  }
}
