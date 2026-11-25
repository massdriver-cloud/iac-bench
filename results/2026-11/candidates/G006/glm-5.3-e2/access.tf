# The application authenticates with the Entra ID identity it already has
# (AKS workload identity / managed identity). Supplying principal_id grants
# exactly the data-plane access the app needs - and nothing else: no keys, no
# connection strings, no management rights on the account.
resource "azurerm_role_assignment" "app_blob_data" {
  count = var.principal_id != null ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "app_file_data" {
  count = var.principal_id != null && length(var.file_shares) > 0 ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.principal_id
}
