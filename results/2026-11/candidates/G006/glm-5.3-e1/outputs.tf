# =============================================================================
# Outputs - what the application actually needs
# =============================================================================

output "storage_account_name" {
  description = "Name of the storage account. This is the value applications use to connect (Azure SDK: account name / endpoint host)."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account, e.g. for granting extra access elsewhere."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Primary blob endpoint of the account, e.g. https://stordersstgxxxx.blob.core.windows.net"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "The containers, keyed by name: id and full blob URL for each."
  value = {
    for name, c in azurerm_storage_container.this :
    name => {
      id  = c.id
      url = "${azurerm_storage_account.this.primary_blob_endpoint}/${name}"
    }
  }
}

output "role_assignment_ids" {
  description = "The role assignment IDs created for the application identities, keyed by identity object ID."
  value = {
    for principal_id, assignment in azurerm_role_assignment.app_identity :
    principal_id => assignment.id
  }
}

output "private_endpoint_id" {
  description = "Resource ID of the blob private endpoint, or null when private networking is not used."
  value       = one(azurerm_private_endpoint.blob[*].id)
}
