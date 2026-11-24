data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "this" {
  count = var.location == null ? 1 : 0
  name  = local.resource_group_name
}

# -----------------------------------------------------------------------------
# Storage Account (StorageV2, Entra ID OAuth Only, TLS 1.2+, Double Encryption)
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                              = local.storage_account_name
  resource_group_name               = local.resource_group_name
  location                          = local.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = local.replication_type
  access_tier                       = "Hot"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = local.public_network_access_enabled

  blob_properties {
    versioning_enabled       = var.enable_versioning
    change_feed_enabled      = local.enable_change_feed
    last_access_time_enabled = true

    delete_retention_policy {
      days                     = local.soft_delete_days
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }

    dynamic "cors_rule" {
      for_each = var.cors_rules

      content {
        allowed_origins    = cors_rule.value.allowed_origins
        allowed_methods    = [for m in cors_rule.value.allowed_methods : upper(m)]
        allowed_headers    = cors_rule.value.allowed_headers
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
  }

  network_rules {
    default_action             = local.network_default_action
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Private Blob Containers (ARM Control-Plane Provisioned)
# -----------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
  metadata              = coalesce(each.value.metadata, {})
}

# -----------------------------------------------------------------------------
# Automated Cost Optimization & Lifecycle Hygiene
# -----------------------------------------------------------------------------

resource "azurerm_storage_management_policy" "this" {
  count              = local.create_lifecycle_policy ? 1 : 0
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.enable_lifecycle_policy ? [1] : []

    content {
      name    = "default-storage-hygiene"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.default_cool_after_days
          tier_to_cold_after_days_since_last_access_time_greater_than = var.default_cold_after_days
          auto_tier_to_hot_from_cool_enabled                          = true
        }

        dynamic "version" {
          for_each = var.enable_versioning ? [1] : []

          content {
            delete_after_days_since_creation = local.noncurrent_version_retention_days
          }
        }

        snapshot {
          delete_after_days_since_creation_greater_than = local.noncurrent_version_retention_days
        }
      }
    }
  }

  dynamic "rule" {
    for_each = local.containers_with_custom_lifecycle

    content {
      name    = "container-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_last_access_time_greater_than = rule.value.cool_after_days
          auto_tier_to_hot_from_cool_enabled                          = rule.value.cool_after_days != null ? true : null
          tier_to_cold_after_days_since_last_access_time_greater_than = rule.value.cold_after_days
          delete_after_days_since_modification_greater_than           = rule.value.delete_after_days
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Entra ID Data-Plane RBAC Assignments (Zero Shared Keys)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_principal_id
}

resource "azurerm_role_assignment" "app_blob_delegator" {
  count                = var.enable_user_delegation_sas ? 1 : 0
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = var.app_principal_id
}

resource "azurerm_role_assignment" "additional_blob_contributor" {
  for_each             = local.additional_contributor_ids
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "additional_blob_delegator" {
  for_each             = local.additional_delegator_ids
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_reader" {
  for_each             = local.reader_ids
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

# -----------------------------------------------------------------------------
# Optional Private Endpoint (Blob Subresource in Application Resource Group)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "blob" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-${local.storage_account_name}-blob"
  location            = local.location
  resource_group_name = local.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Optional Blob Service Audit Diagnostics & Deletion Protection Lock
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "${local.storage_account_name}-blob-diagnostics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_management_lock" "this" {
  count      = var.enable_delete_lock ? 1 : 0
  name       = "lock-${local.storage_account_name}-cannot-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Prevents accidental deletion of the ${var.app_name} (${local.normalized_environment}) storage account."
}
