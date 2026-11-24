output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "HTTPS endpoint for Blob Storage (use with Entra ID / DefaultAzureCredential; shared access keys are disabled)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of created private blob container names to their Azure Resource Manager IDs."
  value = {
    for name, container in azurerm_storage_container.this : name => container.resource_manager_id
  }
}

output "contributor_role_assignment_ids" {
  description = "Map of Entra ID principal IDs to their Storage Blob Data Contributor role assignment IDs."
  value = {
    for principal_id, ra in azurerm_role_assignment.blob_contributor : principal_id => ra.id
  }
}

output "reader_role_assignment_ids" {
  description = "Map of Entra ID principal IDs to their Storage Blob Data Reader role assignment IDs."
  value = {
    for principal_id, ra in azurerm_role_assignment.blob_reader : principal_id => ra.id
  }
}
