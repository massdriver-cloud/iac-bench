resource "random_string" "suffix" {
  count   = var.storage_account_name_override == null ? 1 : 0
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false

  keepers = {
    app_name            = local.clean_app
    environment         = local.clean_env
    resource_group_name = lower(var.resource_group_name)
  }
}

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = var.access_tier

  # Identity-first security baseline: TLS 1.2+, Entra ID OAuth only, no shared keys, no public blobs
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  public_network_access_enabled     = local.public_network_access_enabled

  network_rules {
    default_action             = local.network_default_action
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = local.normalized_ip_rules
    virtual_network_subnet_ids = sort(tolist(var.allowed_subnet_ids))
  }

  blob_properties {
    versioning_enabled       = var.versioning_enabled
    change_feed_enabled      = var.change_feed_enabled
    last_access_time_enabled = true

    dynamic "delete_retention_policy" {
      for_each = local.soft_delete_days > 0 ? [local.soft_delete_days] : []
      content {
        days = delete_retention_policy.value
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = local.soft_delete_days > 0 ? [local.soft_delete_days] : []
      content {
        days = container_delete_retention_policy.value
      }
    }

    dynamic "cors_rule" {
      for_each = var.cors_rules
      content {
        allowed_origins    = cors_rule.value.allowed_origins
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_headers    = cors_rule.value.allowed_headers
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
  metadata              = each.value.metadata
}

resource "azurerm_storage_management_policy" "this" {
  count              = local.enable_management_policy ? 1 : 0
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = local.enable_version_cleanup_rule ? [1] : []
    content {
      name    = "cleanup-noncurrent-versions-and-snapshots"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        version {
          delete_after_days_since_creation = local.noncurrent_version_days
        }
        snapshot {
          delete_after_days_since_creation_greater_than = local.noncurrent_version_days
        }
      }
    }
  }

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
          tier_to_cool_after_days_since_modification_greater_than = rule.value.cool_after_days
          tier_to_cold_after_days_since_modification_greater_than = rule.value.cold_after_days
          delete_after_days_since_modification_greater_than       = rule.value.delete_after_days
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Entra ID Role-Based Access Control
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "app_blob_delegator" {
  count                = var.enable_user_delegation_sas ? 1 : 0
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "additional_blob_contributors" {
  for_each = var.additional_contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value

  lifecycle {
    precondition {
      condition     = lower(each.value) != lower(var.principal_id)
      error_message = "principal_id is already granted Storage Blob Data Contributor; do not duplicate it in additional_contributor_principal_ids."
    }
  }
}

resource "azurerm_role_assignment" "additional_blob_delegators" {
  for_each = var.enable_user_delegation_sas ? var.additional_contributor_principal_ids : toset([])

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "additional_blob_readers" {
  for_each = local.additional_reader_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value

  lifecycle {
    precondition {
      condition     = lower(each.value) != lower(var.principal_id)
      error_message = "principal_id already has Storage Blob Data Contributor access; do not duplicate it in additional_reader_principal_ids."
    }
  }
}

# -----------------------------------------------------------------------------
# Optional Private Endpoint (AKS / App Service VNet Private Link)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "blob" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-${local.storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
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
# Optional Diagnostics & Accidental-Deletion Protection
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "account" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${local.storage_account_name}-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${local.storage_account_name}-blob"
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
  notes      = "Protects ${var.app_name} (${var.environment}) application storage account from accidental deletion."
}
