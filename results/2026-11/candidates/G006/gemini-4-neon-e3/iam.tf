# Least-privilege Entra ID data-plane RBAC assignments.
# Applications authenticate via Managed Identity (App Service) or Workload Identity (AKS)
# using DefaultAzureCredential — no storage account keys or SAS secrets required.

resource "azurerm_role_assignment" "blob_contributor" {
  for_each = local.contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_reader" {
  for_each = setsubtract(var.reader_principal_ids, local.contributor_principal_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
