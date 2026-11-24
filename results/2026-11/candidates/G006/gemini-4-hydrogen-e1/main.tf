resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  account_replication_type = local.replication_type

  # Enforce Entra ID authentication and modern transport/encryption defaults.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  is_hns_enabled                    = false
  nfsv3_enabled                     = false
  sftp_enabled                      = false

  public_network_access_enabled = local.public_network_access_enabled

  blob_properties {
    versioning_enabled = local.versioning_enabled

    delete_retention_policy {
      days = local.blob_soft_delete_days
    }

    container_delete_retention_policy {
      days = local.container_soft_delete_days
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "HEAD", "OPTIONS", "POST", "PUT"]
        allowed_origins    = var.cors_allowed_origins
        exposed_headers    = ["ETag", "x-ms-request-id", "x-ms-version"]
        max_age_in_seconds = 3600
      }
    }
  }

  network_rules {
    default_action             = local.network_default_action
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  count = local.has_lifecycle_policy ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = local.versioning_enabled ? [1] : []
    content {
      name    = "expire-noncurrent-versions"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        version {
          delete_after_days_since_creation = 90
        }
      }
    }
  }

  dynamic "rule" {
    for_each = local.containers_with_lifecycle
    content {
      name    = "container-${rule.key}"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than = rule.value.lifecycle_tier_to_cool_after_days
          tier_to_cold_after_days_since_modification_greater_than = rule.value.lifecycle_tier_to_cold_after_days
          delete_after_days_since_modification_greater_than       = rule.value.lifecycle_delete_after_days
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "application" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.application_principal_id
}

resource "azurerm_role_assignment" "additional" {
  for_each = var.additional_role_assignments

  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

resource "azurerm_private_endpoint" "blob" {
  count = local.has_private_endpoint ? 1 : 0

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

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

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
