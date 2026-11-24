output "storage_account_id" {
  description = "Resource ID of the application's storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Storage account name for SDK configuration."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS endpoint for use with an Azure SDK and Entra ID credentials. No keys or connection strings are required."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "containers" {
  description = "Container names mapped to ARM IDs and HTTPS URLs. Authentication is required."
  value = {
    for name, container in azurerm_storage_container.application : name => {
      id  = container.resource_manager_id
      url = "${azurerm_storage_account.application.primary_blob_endpoint}${name}"
    }
  }
}
