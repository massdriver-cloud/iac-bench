output "storage_account_id" {
  description = "ID of the storage account (ARM resource ID)."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account. Use this - not a connection string - as the account name in your SDK settings."
  value       = azurerm_storage_account.this.name
}

output "location" {
  description = "Azure region the storage account lives in."
  value       = local.location
}

output "blob_endpoint" {
  description = "Blob endpoint URL of the storage account, e.g. https://<account>.blob.core.windows.net/."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the blob containers created for the application."
  value       = sort([for container in azurerm_storage_container.this : container.name])
}

output "private_dns_zone_id" {
  description = "Private DNS zone the blob private endpoints are registered in. Null when private endpoints are not used. Reuse this in `private_dns_zone_id` if you create a second storage account in the same resource group."
  value       = local.blob_private_dns_zone_id
}

output "private_endpoint_ids" {
  description = "IDs of the blob private endpoints, keyed by subnet index (01, 02, ...). Empty when private endpoints are not used."
  value       = { for key, endpoint in azurerm_private_endpoint.blob : key => endpoint.id }
}
