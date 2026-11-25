locals {
  is_prod = var.environment == "prod"

  # Storage account names are globally unique, 3-24 chars, lowercase alphanumeric.
  # Layout: "st" + app + env (truncated to 18) + 4 random chars = max 24.
  name_base            = substr(replace("${var.application_name}${var.environment}", "-", ""), 0, 18)
  storage_account_name = "st${local.name_base}${random_string.suffix.result}"

  replication_type = coalesce(var.replication_type, local.is_prod ? "ZRS" : "LRS")

  # Lock the network down only when the team tells us where the app lives;
  # otherwise keep the account reachable (identity + TLS still enforced).
  network_restricted = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  # How long deleted blobs / containers can be recovered, and how long old
  # versions of overwritten blobs are kept before lifecycle management removes them.
  soft_delete_days   = local.is_prod ? 30 : 7
  version_retention  = local.is_prod ? 90 : 30
  snapshot_retention = local.version_retention

  tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed-by  = "opentofu"
      module      = "app-storage"
    },
    var.tags,
  )
}

resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Transport and authentication hardening.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false # applications use their Entra ID identity, never keys
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false # no anonymous/public blobs, ever
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false # no SFTP local users
  sftp_enabled                      = false

  public_network_access_enabled = true

  network_rules {
    default_action             = local.network_restricted ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }
  }

  tags = local.tags

  lifecycle {
    # Changing the name would replace the account and destroy every file in it.
    ignore_changes = [name]
  }
}

# One private container per logical file category (uploads, exports, ...).
# Managed through the resource-manager API so no shared key is needed.
resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Keep versioning from growing without bound: old versions and snapshots of
# overwritten blobs are removed after the retention window. Current blobs are
# never touched by this rule.
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-old-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.version_retention
      }
      snapshot {
        delete_after_days_since_creation_greater_than = local.snapshot_retention
      }
    }
  }
}

# The application's own identity gets read/write access to blob data in this
# account. This is the only way the application is expected to reach its files.
resource "azurerm_role_assignment" "application_blob_access" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
}
