output "storage_account_id" {
  description = "ARM resource ID of the application's storage account."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Storage account name (not a credential)."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS blob service URL for the Azure SDK. Authenticate using the application's Entra identity."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "containers" {
  description = "Container names mapped to their ARM IDs and SDK URLs."
  value = {
    for name, container in azurerm_storage_container.application : name => {
      id  = container.resource_manager_id
      url = "${azurerm_storage_account.application.primary_blob_endpoint}${name}"
    }
  }
}
