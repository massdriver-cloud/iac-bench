# Every application already has its own identity in Entra ID. Grant each one
# read/write access to blob data on the account with the built-in data-plane
# role - this is what makes AKS workload identity and App Service managed
# identity "just work" against the account (especially with keys disabled).
resource "azurerm_role_assignment" "blob_data_contributor" {
  for_each = var.app_identity_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
