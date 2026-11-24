output "storage_account_id" {
  description = "Resource ID of the application storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the application storage account. Use this with an Azure SDK and the application's Entra ID credential."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "HTTPS blob service endpoint used by application SDKs."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Created private containers, keyed by requested name, with their resource IDs and application URLs."
  value = {
    for name, container in azurerm_storage_container.this : name => {
      id   = container.id
      name = container.name
      url  = "${azurerm_storage_account.this.primary_blob_endpoint}${container.name}"
    }
  }
}

output "application_role_assignment_id" {
  description = "Resource ID of the application's Storage Blob Data Contributor assignment."
  value       = azurerm_role_assignment.application_blob_data.id
}
