# Azure file shares are opt-in: only when something genuinely needs SMB
# (App Service content mounts, legacy tooling). Each share gets the quota the
# team picks, and blob storage - which is what this module is really about -
# stays the default answer.
resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value
}
