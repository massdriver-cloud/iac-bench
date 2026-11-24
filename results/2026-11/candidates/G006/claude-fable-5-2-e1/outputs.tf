output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service URL, e.g. https://stordersprod1a2b3c.blob.core.windows.net/. Give this to the Azure SDK together with DefaultAzureCredential / workload identity - there is no key or connection string."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Names of the containers that were created."
  value       = sort(keys(azurerm_storage_container.this))
}

output "container_urls" {
  description = "URL of each container, keyed by container name."
  value = {
    for name, c in azurerm_storage_container.this :
    name => "${azurerm_storage_account.this.primary_blob_endpoint}${c.name}"
  }
}

output "app_settings" {
  description = "Ready-made, non-secret settings for the application (App Service app settings or AKS pod environment variables)."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
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
  value       = one(azurerm_private_endpoint.blob[*].private_service_connection[0].private_ip_address)
}

output "network_access" {
  description = "Summary of where the storage account can be reached from. If this says \"none\", set allowed_subnet_ids or private_endpoint_subnet_id so the application can reach its files."
  value = (
    var.allow_public_network_access ? "all networks (identity still required)" :
    length(var.allowed_subnet_ids) + length(var.allowed_ip_ranges) > 0 || var.private_endpoint_subnet_id != null ? "selected networks only" :
    "none"
  )
}
