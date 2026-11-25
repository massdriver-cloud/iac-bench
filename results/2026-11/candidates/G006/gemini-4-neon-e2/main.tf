resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = var.access_tier

  # Security hardening — Entra ID auth only, TLS 1.2+, HTTPS only, no anonymous access, double encryption
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  allowed_copy_scope                = "AAD"

  # Disable unused protocols/surfaces (blob-focused application file storage)
  is_hns_enabled           = false
  nfsv3_enabled            = false
  sftp_enabled             = false
  local_user_enabled       = false
  large_file_share_enabled = false

  # Network posture — private-only when Private Endpoint is used, default-deny firewall otherwise
  public_network_access_enabled = local.public_network_access_enabled

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  # Recommend short-lived User Delegation SAS tokens (for direct browser uploads/downloads)
  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  # Blob data protection — versioning, soft delete, optional PITR (on by default in prod), optional CORS
  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = local.pitr_days > 0
    change_feed_retention_in_days = local.pitr_days > 0 ? local.blob_soft_delete_days : null

    delete_retention_policy {
      days = local.blob_soft_delete_days
    }

    container_delete_retention_policy {
      days = local.container_soft_delete_days
    }

    dynamic "restore_policy" {
      for_each = local.pitr_days > 0 ? [1] : []
      content {
        days = local.pitr_days
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

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.pitr_days == 0 || local.pitr_days < local.blob_soft_delete_days
      error_message = "point_in_time_restore_days (${local.pitr_days}) must be strictly less than blob_soft_delete_days (${local.blob_soft_delete_days})."
    }
  }
}

# Private blob containers managed via ARM control plane (works with shared_access_key_enabled = false and firewall Deny)
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Lifecycle management: always expire old non-current versions to prevent unbounded versioning cost,
# plus per-container tiering and expiration rules (e.g., for generated reports and exports).
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "cleanup-previous-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.previous_version_retention_days
      }
    }
  }

  dynamic "rule" {
    for_each = local.containers_with_lifecycle
    content {
      name    = "lifecycle-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.cool_after_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.archive_after_days
          delete_after_days_since_modification_greater_than          = rule.value.expire_after_days
        }

        dynamic "version" {
          for_each = rule.value.expire_after_days != null ? [1] : []
          content {
            delete_after_days_since_creation = rule.value.expire_after_days
          }
        }
      }
    }
  }
}

# Prevent accidental deletion of production storage accounts
resource "azurerm_management_lock" "this" {
  count = local.enable_delete_lock ? 1 : 0

  name       = "lock-cannot-delete-${local.storage_account_name}"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects ${var.app_name} (${var.environment}) application storage from accidental deletion."
}
