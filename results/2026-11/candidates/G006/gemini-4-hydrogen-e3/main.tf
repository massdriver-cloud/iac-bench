resource "random_string" "suffix" {
  length  = 6
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
  access_tier              = var.access_tier

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  public_network_access_enabled     = local.public_network_access_enabled

  blob_properties {
    versioning_enabled = var.versioning_enabled

    delete_retention_policy {
      days = local.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "HEAD", "PUT", "OPTIONS"]
        allowed_origins    = var.cors_allowed_origins
        exposed_headers    = ["ETag", "x-ms-request-id"]
        max_age_in_seconds = 3600
      }
    }
  }

  dynamic "network_rules" {
    for_each = local.restrict_network || local.use_private_endpoint ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices", "Logging", "Metrics"]
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  count = local.create_management_policy ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.versioning_enabled ? [1] : []
    content {
      name    = "cleanup-noncurrent-versions"
      enabled = true

      filters {
        blob_types = ["blockBlob"]
      }

      actions {
        version {
          delete_after_days_since_creation = var.noncurrent_version_retention_days
        }
      }
    }
  }

  dynamic "rule" {
    for_each = local.container_lifecycle_rules
    content {
      name    = "container-${rule.key}-lifecycle"
      enabled = true

      filters {
        blob_types   = ["blockBlob"]
        prefix_match = ["${rule.key}/"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than = rule.value.cool_after_days
          delete_after_days_since_modification_greater_than       = rule.value.expire_after_days
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "contributors" {
  for_each = local.contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "readers" {
  for_each = local.reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

resource "azurerm_private_endpoint" "blob" {
  count = local.use_private_endpoint ? 1 : 0

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

  tags = local.common_tags
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
