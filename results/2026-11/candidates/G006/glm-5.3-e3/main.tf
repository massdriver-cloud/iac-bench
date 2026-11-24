# The application's resource group already exists - each application has one
# per environment. It is only read (to learn its location) when the team does
# not pin `location` explicitly.
data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0

  name = var.resource_group_name
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = local.location

  # The right shape for application file storage: general-purpose v2,
  # standard performance, hot access tier. Old data is moved to Cool by the
  # lifecycle policy below, not by the account's default access tier.
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Secure by default: HTTPS only with TLS 1.2 as the floor, no anonymous blob
  # access, no replication into other tenants, double encryption at rest, and
  # - because the applications sign in with their Entra ID identities - no
  # storage account keys at all. Local users are off too: they exist for
  # SFTP-style access this module does not set up.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = var.allow_shared_key_access
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false

  public_network_access_enabled = local.public_network_access_enabled

  dynamic "network_rules" {
    for_each = local.network_rules_required ? [1] : []

    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      ip_rules       = length(var.allowed_ip_ranges) > 0 ? var.allowed_ip_ranges : null
    }
  }

  # Data protection: blobs and whole containers that were deleted or
  # overwritten by mistake can be recovered for 14 days, and every overwrite
  # of a blob keeps the previous version around (the lifecycle policy cleans
  # those up after `days_to_keep_versions`).
  blob_properties {
    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }

    versioning_enabled  = true
    change_feed_enabled = false
  }

  tags = local.tags
}

# One container per kind of application file. Containers are private: access
# happens with the application's identity, never through public blobs.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Lifecycle management: blobs that have not been touched for a while are
# tiered down to Cool storage, and old blob versions are removed. Nothing is
# ever deleted unless the team explicitly opts into `days_to_delete`.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tierOldBlobs"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = local.blob_lifecycle_days.days_to_cool
        tier_to_archive_after_days_since_modification_greater_than = local.blob_lifecycle_days.days_to_archive
        delete_after_days_since_modification_greater_than          = local.blob_lifecycle_days.days_to_delete
      }
    }
  }

  rule {
    name    = "cleanupBlobVersions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.blob_lifecycle_days.days_to_keep_versions
      }
    }
  }
}

# The application's identities get data-plane access to the blobs: read,
# write and delete on every container in the account. New role assignments
# can take a few minutes to become active after the first apply.
resource "azurerm_role_assignment" "app_blob_data_contributor" {
  for_each = var.app_identity_object_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}
