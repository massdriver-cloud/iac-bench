# =============================================================================
# Azure Subscription Context (Used for Deterministic Globally Unique Naming)
# =============================================================================

data "azurerm_client_config" "current" {}

# =============================================================================
# Core Storage Account
# =============================================================================

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = var.access_tier

  # Security & Authentication: Entra ID (OAuth) only, HTTPS + TLS 1.2+, no anonymous public blobs
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  # Disable unused protocols to minimize attack surface (apps use Blob API via Entra ID)
  local_user_enabled = false
  sftp_enabled       = false
  is_hns_enabled     = false
  nfsv3_enabled      = false

  # Network perimeter
  public_network_access_enabled = local.public_network_access_enabled

  network_rules {
    default_action             = var.network_default_action
    bypass                     = var.network_bypass
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  # Data protection: soft delete, versioning, change feed, and optional PITR + CORS
  blob_properties {
    versioning_enabled            = local.versioning_enabled
    change_feed_enabled           = local.change_feed_enabled
    change_feed_retention_in_days = local.change_feed_enabled ? local.blob_soft_delete_days : null

    delete_retention_policy {
      days                     = local.blob_soft_delete_days
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = local.container_soft_delete_days
    }

    dynamic "restore_policy" {
      for_each = local.point_in_time_restore_days != null ? [local.point_in_time_restore_days] : []
      content {
        days = restore_policy.value
      }
    }

    dynamic "cors_rule" {
      for_each = var.cors_rules
      content {
        allowed_headers    = cors_rule.value.allowed_headers
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_origins    = cors_rule.value.allowed_origins
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
  }

  routing {
    choice = "MicrosoftRouting"
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.point_in_time_restore_days == null || local.versioning_enabled
      error_message = "Point-in-time restore requires blob versioning to be enabled (versioning_enabled = true)."
    }

    precondition {
      condition     = local.point_in_time_restore_days == null || local.point_in_time_restore_days < local.blob_soft_delete_days
      error_message = "point_in_time_restore_days must be strictly less than blob_soft_delete_days (Azure requirement)."
    }
  }
}

# =============================================================================
# Blob Containers (Always Private, Created via ARM Control Plane)
# =============================================================================

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# =============================================================================
# Lifecycle Management Policy (Version Cleanup + Per-Container Tiering/Expiry)
# =============================================================================

resource "azurerm_storage_management_policy" "this" {
  count = local.has_lifecycle_policy ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  # Automatically expire old noncurrent versions so overwrite protection does not cause unbounded cost growth.
  dynamic "rule" {
    for_each = local.versioning_enabled ? [1] : []
    content {
      name    = "cleanup-noncurrent-versions"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        version {
          delete_after_days_since_creation = local.noncurrent_version_retention_days
        }
      }
    }
  }

  # Per-container tiering and expiration rules declared in var.containers.
  dynamic "rule" {
    for_each = local.container_lifecycle_rules
    content {
      name    = "container-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.tier_to_cool_after_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.tier_to_archive_after_days
          delete_after_days_since_modification_greater_than          = rule.value.delete_after_days
        }
      }
    }
  }

  # Optional custom prefix-based lifecycle rules for fine-grained sub-container policies.
  dynamic "rule" {
    for_each = { for r in var.additional_lifecycle_rules : r.name => r }
    content {
      name    = rule.value.name
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = rule.value.prefix_match
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.tier_to_cool_after_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.tier_to_archive_after_days
          delete_after_days_since_modification_greater_than          = rule.value.delete_after_days
        }
      }
    }
  }
}

# =============================================================================
# Accidental Deletion Lock (Enabled by Default in Production)
# =============================================================================

resource "azurerm_management_lock" "this" {
  count = local.enable_delete_lock ? 1 : 0

  name       = "lock-${azurerm_storage_account.this.name}-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by OpenTofu: prevents accidental deletion of ${var.application_name} (${var.environment}) storage account."
}
