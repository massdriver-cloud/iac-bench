# Primary application Entra ID identity (AKS Workload Identity / App Service Managed Identity)
resource "azurerm_role_assignment" "app_writer" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_principal_id
}

# Additional account-wide read/write identities
resource "azurerm_role_assignment" "additional_writers" {
  for_each = var.additional_writer_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

# Account-wide read-only identities
resource "azurerm_role_assignment" "account_readers" {
  for_each = local.account_reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

# Container-scoped read/write identities (least-privilege container sharing)
resource "azurerm_role_assignment" "container_writers" {
  for_each = local.container_writer_assignments

  scope                = azurerm_storage_container.this[each.value.container].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
}

# Container-scoped read-only identities (for example, downstream consumers of 'exports')
resource "azurerm_role_assignment" "container_readers" {
  for_each = local.container_reader_assignments

  scope                = azurerm_storage_container.this[each.value.container].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value.principal_id
}
