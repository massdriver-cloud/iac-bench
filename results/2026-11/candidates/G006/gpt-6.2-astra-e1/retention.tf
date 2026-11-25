# Bound the cost of overwrites without expiring live application files.
resource "azurerm_storage_management_policy" "history" {
  storage_account_id = azurerm_storage_account.app.id

  rule {
    name    = "expirePreviousVersions"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${azurerm_storage_container.files.name}/"]
    }
    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}
