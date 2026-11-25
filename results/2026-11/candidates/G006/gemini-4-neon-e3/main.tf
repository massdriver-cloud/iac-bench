# Globally unique, stable alphanumeric suffix for Azure Storage Account naming.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false

  keepers = {
    application_name    = var.application_name
    environment         = var.environment
    resource_group_name = var.resource_group_name
  }
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  # Security baseline: Entra ID only, HTTPS/TLS 1.2+, no anonymous public blobs,
  # double encryption at rest, no SFTP/local users, no cross-tenant replication.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  sftp_enabled                      = false
  is_hns_enabled                    = false
  public_network_access_enabled     = local.public_network_access_enabled

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = local.is_prod
    change_feed_retention_in_days = local.is_prod ? local.blob_soft_delete_days : null
    last_access_time_enabled      = var.enable_auto_tiering

    delete_retention_policy {
      days = local.blob_soft_delete_days
    }

    container_delete_retention_policy {
      days = local.container_soft_delete_days
    }

    # Point-in-time restore is enabled automatically in prod (requires versioning,
    # change feed, and delete_retention_policy.days > restore_policy.days).
    dynamic "restore_policy" {
      for_each = local.is_prod ? [1] : []
      content {
        days = local.point_in_time_restore_days
      }
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers = [
          "authorization",
          "content-type",
          "x-ms-blob-type",
          "x-ms-blob-content-type",
          "x-ms-date",
          "x-ms-version",
        ]
        allowed_methods = ["GET", "HEAD", "PUT", "OPTIONS"]
        allowed_origins = var.cors_allowed_origins
        exposed_headers = [
          "content-length",
          "content-type",
          "etag",
          "x-ms-request-id",
          "x-ms-version",
        ]
        max_age_in_seconds = 3600
      }
    }
  }

  # Deny public internet traffic by default; allow explicitly configured AKS/App Service
  # subnets, approved egress IPs, and Azure platform services (Logging/Metrics/AzureServices).
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.standard_tags

  lifecycle {
    precondition {
      condition     = var.private_dns_zone_id == null || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_id can only be set when private_endpoint_subnet_id is also provided."
    }
  }
}

# Private blob containers provisioned via ARM control plane (storage_account_id),
# so creation succeeds even with shared_access_key_enabled = false and firewall Deny.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Automated cost & retention lifecycle management:
# 1. Moves untouched blobs to Cool/Cold and auto-rehydrates back to Hot on access.
# 2. Cleans up old noncurrent blob versions so versioning does not grow costs indefinitely.
# 3. Expires blobs in containers that declare retention_days (e.g. generated reports/exports).
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.enable_auto_tiering ? [1] : []
    content {
      name    = "auto-tier-untouched-blobs"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.cool_tier_after_days
          tier_to_cold_after_days_since_last_access_time_greater_than = var.cold_tier_after_days
          auto_tier_to_hot_from_cool_enabled                          = true
        }
      }
    }
  }

  rule {
    name    = "cleanup-noncurrent-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = local.noncurrent_version_delete_day
      }
    }
  }

  dynamic "rule" {
    for_each = local.expiring_containers
    content {
      name    = "expire-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          delete_after_days_since_modification_greater_than = rule.value
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_auto_tiering || var.cold_tier_after_days > var.cool_tier_after_days
      error_message = "cold_tier_after_days must be strictly greater than cool_tier_after_days when enable_auto_tiering is enabled."
    }
  }
}

# Prevent accidental deletion of the storage account in production (or when explicitly enabled).
# Applied last (and removed first on destroy) to avoid ScopeLocked errors on child resources.
resource "azurerm_management_lock" "this" {
  count = local.create_delete_lock ? 1 : 0

  name       = "lock-${local.storage_account_name}-cannot-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by OpenTofu: protects application storage account from accidental deletion."

  depends_on = [
    azurerm_storage_container.this,
    azurerm_storage_management_policy.this,
    azurerm_role_assignment.blob_contributor,
    azurerm_role_assignment.blob_reader,
    azurerm_monitor_diagnostic_setting.storage_account,
    azurerm_monitor_diagnostic_setting.blob_service,
  ]
}
