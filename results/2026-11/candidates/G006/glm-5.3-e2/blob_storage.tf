# One private container per kind of thing the application stores. Access is
# Entra ID only (no keys, no SAS), so they are safe by construction.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Lifecycle policy: the module's cost-control judgement.
#
#   - Block blobs nobody has touched for 30 days move to the cool tier.
#   - Blob versions and snapshots expire after 30 days, which bounds the cost
#     of versioning and soft delete without touching live data.
#   - Base blobs are NEVER deleted automatically. Deciding when application
#     data may be destroyed is an application decision, not a platform one.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tier-stale-blobs-to-cool"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }

  rule {
    name    = "expire-blob-versions-and-snapshots"
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
