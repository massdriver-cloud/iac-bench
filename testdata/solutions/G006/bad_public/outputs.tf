output "storage_account_id" {
  description = "Storage account resource ID, the scope for further role assignments. Shared keys are disabled, so the azurerm provider that applies this module needs storage_use_azuread = true (or ARM_STORAGE_USE_AZUREAD=true)."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  description = "Blob service endpoint; applications authenticate with their Entra ID identities."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Container names."
  value       = sort([for c in azurerm_storage_container.this : c.name])
}
