output "storage_account_name" {
  description = "Name of the storage account. Give this to the application (e.g. as AZURE_STORAGE_ACCOUNT_NAME)."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service URL the application connects to, using its own identity (DefaultAzureCredential / workload identity / managed identity). There is deliberately no connection string or account key."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_urls" {
  description = "Map of container name to its URL."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}"
  }
}

output "resource_group_name" {
  description = "Resource group the storage account lives in."
  value       = azurerm_storage_account.this.resource_group_name
}

output "location" {
  description = "Azure region of the storage account."
  value       = azurerm_storage_account.this.location
}

output "private_endpoint_ip_address" {
  description = "Private IP address of the blob private endpoint, or null when no private endpoint was requested."
  value = one(flatten([
    for pe in local.private_endpoints : [
      for conn in pe.private_service_connection : conn.private_ip_address
    ]
  ]))
}

output "settings" {
  description = "The decisions the module made for this account, for review."
  value = {
    replication_type               = local.replication_type
    recovery_days                  = local.recovery_days
    delete_lock_enabled            = local.delete_lock_enabled
    cool_after_days_without_access = var.cool_after_days_without_access
    network_access = (
      local.has_network_path
      ? join(" + ", compact([
        length(var.allowed_subnet_ids) > 0 ? "${length(var.allowed_subnet_ids)} allowed subnet(s)" : "",
        length(var.allowed_ip_ranges) > 0 ? "${length(var.allowed_ip_ranges)} allowed IP range(s)" : "",
        local.private_endpoint ? "private endpoint" : "",
      ]))
      : "none - blocked until allowed_subnet_ids or private_endpoint_subnet_id is set"
    )
  }
}
