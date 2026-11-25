output "storage_account_id" {
  description = "Azure Resource Manager ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Globally unique name of the provisioned Azure Storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary HTTPS Blob Storage endpoint URL to pass to Azure Blob SDK clients with DefaultAzureCredential."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Hostname of the primary Blob Storage endpoint."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "secondary_blob_endpoint" {
  description = "Secondary HTTPS Blob Storage endpoint URL (populated when read-access geo-redundant replication such as RAGZRS or RAGRS is configured)."
  value       = azurerm_storage_account.this.secondary_blob_endpoint
}

output "containers" {
  description = "Map of provisioned Blob containers keyed by container name, including ARM ID, name, and full HTTPS container URL."
  value = {
    for k, c in azurerm_storage_container.this : k => {
      id   = c.id
      name = c.name
      url  = "${trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/")}/${c.name}"
    }
  }
}

output "app_settings" {
  description = "Ready-to-merge application environment variables suitable for Azure App Service app_settings or an AKS Kubernetes ConfigMap."
  value = {
    AZURE_STORAGE_ACCOUNT_NAME  = azurerm_storage_account.this.name
    AZURE_STORAGE_BLOB_ENDPOINT = azurerm_storage_account.this.primary_blob_endpoint
    AZURE_STORAGE_CONTAINERS    = join(",", sort(keys(azurerm_storage_container.this)))
  }
}

output "private_endpoint_ip" {
  description = "Private IP address assigned to the Blob Private Endpoint, or null when no Private Endpoint is configured."
  value       = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, null)
}
