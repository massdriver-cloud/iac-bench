output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Generated Azure-compliant name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "HTTPS endpoint URL for Blob Storage. Pass this directly to Azure SDK BlobServiceClient with DefaultAzureCredential()."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Hostname of the primary Blob Storage endpoint (without scheme)."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "container_names" {
  description = "List of created blob container names."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_ids" {
  description = "Map of blob container name to Azure Resource Manager resource ID."
  value       = { for name, c in azurerm_storage_container.this : name => c.id }
}

output "container_urls" {
  description = "Map of blob container name to its full HTTPS container URL."
  value       = { for name, c in azurerm_storage_container.this : name => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}" }
}

output "private_endpoint_id" {
  description = "Azure Resource Manager ID of the blob Private Endpoint, or null if not enabled."
  value       = var.private_endpoint != null ? azurerm_private_endpoint.blob[0].id : null
}

output "private_endpoint_ip_address" {
  description = "Private IP address assigned to the blob Private Endpoint, or null if not enabled."
  value       = var.private_endpoint != null ? azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address : null
}

output "effective_configuration" {
  description = "Summary of the opinionated security, resilience, and lifecycle settings applied by this module."
  value = {
    environment                       = var.environment
    replication_type                  = local.replication_type
    access_tier                       = var.access_tier
    shared_access_key_enabled         = false
    oauth_default_authentication      = true
    user_delegation_sas_enabled       = var.enable_user_delegation_sas
    public_blob_access_allowed        = false
    public_network_access_enabled     = local.public_network_access_enabled
    network_default_action            = var.network_default_action
    private_endpoint_enabled          = var.private_endpoint != null
    blob_soft_delete_days             = local.blob_soft_delete_days
    container_soft_delete_days        = local.container_soft_delete_days
    versioning_enabled                = local.versioning_enabled
    change_feed_enabled               = local.change_feed_enabled
    point_in_time_restore_days        = local.point_in_time_restore_days
    noncurrent_version_retention_days = local.noncurrent_version_retention_days
    delete_lock_enabled               = local.enable_delete_lock
    diagnostics_enabled               = var.log_analytics_workspace_id != null
    malware_scanning_enabled          = var.enable_malware_scanning
  }
}
