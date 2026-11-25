# Least-privilege Entra ID RBAC role assignments for application identities.
# Storage Blob Data Contributor grants read/write/delete on blobs and containers
# plus generateUserDelegationKey for short-lived User Delegation SAS URLs.
resource "azurerm_role_assignment" "blob_contributor" {
  for_each = local.contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

# Optional read-only access for downstream consumers or support identities.
resource "azurerm_role_assignment" "blob_reader" {
  for_each = var.reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
