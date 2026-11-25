output "storage_account_id" {
  description = "Storage account ARM resource ID."
  value       = azurerm_storage_account.application.id
}

output "storage_account_name" {
  description = "Storage account name for application SDK configuration."
  value       = azurerm_storage_account.application.name
}

output "blob_endpoint" {
  description = "HTTPS blob service URL. Use this with Azure Identity credentials, not account keys."
  value       = azurerm_storage_account.application.primary_blob_endpoint
}

output "containers" {
  description = "Container names mapped to their ARM IDs and HTTPS URLs."
  value = {
    for name, container in azurerm_storage_container.application : name => {
      id  = container.resource_manager_id
      url = "${azurerm_storage_account.application.primary_blob_endpoint}${name}"
    }
  }
}
