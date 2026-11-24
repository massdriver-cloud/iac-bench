# Versioning protects application data, but without a lifecycle rule every
# noncurrent version would be retained forever. Active blobs are deliberately
# untouched: this rule only expires noncurrent versions and snapshots.
resource "azurerm_storage_management_policy" "data_protection" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-noncurrent-data"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }

      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}
