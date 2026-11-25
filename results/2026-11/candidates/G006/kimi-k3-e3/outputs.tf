# Deliberately NOT output: account keys, connection strings, SAS tokens.
# Apps authenticate with their Entra ID identity; nothing here hands out
# secrets.

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob endpoint the application should talk to (e.g. https://stordersstaginga1b2c3d4.blob.core.windows.net/)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of container name to its resource ID and URL."
  value = {
    for name, c in azurerm_storage_container.this :
    name => {
      id  = c.id
      url = "${trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")}/${c.name}"
    }
  }
}

output "app_identity_role_assignment_id" {
  description = "ID of the role assignment granting the application's identity Storage Blob Data Contributor on the account."
  value       = azurerm_role_assignment.app_data_plane.id
}
