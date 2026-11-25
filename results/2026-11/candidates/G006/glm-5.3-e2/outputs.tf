output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account, derived deterministically from the application and resource group names."
  value       = azurerm_storage_account.this.name
}

output "location" {
  description = "Azure region the storage account was created in."
  value       = local.location
}

output "replication_type" {
  description = "Replication configured on the account (module default or override)."
  value       = local.replication_type
}

output "blob_endpoint" {
  description = "Primary blob endpoint URL, e.g. https://<account>.blob.core.windows.net/."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "file_endpoint" {
  description = "Primary Azure Files endpoint URL (SMB and REST)."
  value       = azurerm_storage_account.this.primary_file_endpoint
}

output "container_names" {
  description = "Blob containers created for the application."
  value       = sort([for c in azurerm_storage_container.this : c.name])
}

output "file_share_names" {
  description = "Azure file shares created (empty unless file_shares was set)."
  value       = sort(keys(azurerm_storage_share.this))
}

output "app_identity_role_assignment_ids" {
  description = "IDs of the data-plane role assignments granted to the application identity (empty unless principal_id was set)."
  value = concat(
    azurerm_role_assignment.app_blob_data[*].id,
    azurerm_role_assignment.app_file_data[*].id
  )
}

output "private_endpoint_ids" {
  description = "Private endpoint resource IDs, keyed by service (blob / file). Empty unless private_endpoint_subnet_id was set."
  value       = { for service, pe in azurerm_private_endpoint.this : service => pe.id }
}
