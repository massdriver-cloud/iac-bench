output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Generated (globally unique) name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint. Use this with Azure SDK DefaultAzureCredential / ManagedIdentityCredential - the app's Entra identity is already authorised. There are no access keys."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Blob service hostname (without scheme)."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "resource_group_name" {
  description = "Resource group the storage account lives in (the application's own resource group)."
  value       = data.azurerm_resource_group.app.name
}

output "location" {
  description = "Azure region of the storage account (inherited from the application's resource group)."
  value       = azurerm_storage_account.this.location
}

output "blob_container_names" {
  description = "Names of the private blob containers created for the application."
  value       = [for c in azurerm_storage_container.app : c.name]
}

output "application_role_assignment_id" {
  description = "Role assignment granting the application's Entra identity Storage Blob Data Contributor on the account."
  value       = azurerm_role_assignment.app_blob_contributor.id
}
