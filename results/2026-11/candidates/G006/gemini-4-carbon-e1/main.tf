resource "random_string" "storage_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    app_name            = var.app_name
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

  # Security & Authentication Baseline:
  # Enforce Entra ID RBAC, TLS 1.2+, HTTPS-only, double encryption, and zero public blobs
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  sftp_enabled                      = false
  is_hns_enabled                    = false
  nfsv3_enabled                     = false
  public_network_access_enabled     = local.public_network_access_enabled

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = local.soft_delete_days
    last_access_time_enabled      = true

    delete_retention_policy {
      days                     = local.soft_delete_days
      permanent_delete_enabled = false
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }

    dynamic "restore_policy" {
      for_each = local.pitr_days > 0 ? [local.pitr_days] : []
      content {
        days = restore_policy.value
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

  network_rules {
    default_action             = local.network_default_action
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    ip_rules                   = local.normalized_ip_rules
    virtual_network_subnet_ids = sort(tolist(var.allowed_subnet_ids))
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.pitr_days < local.soft_delete_days
      error_message = "point_in_time_restore_days (${local.pitr_days}) must be strictly less than soft_delete_retention_days (${local.soft_delete_days})."
    }

    precondition {
      condition = (
        var.default_cool_after_days == null ||
        var.default_cold_after_days == null ||
        var.default_cold_after_days > var.default_cool_after_days
      )
      error_message = "default_cold_after_days must be greater than default_cool_after_days when both are enabled."
    }

    precondition {
      condition     = length(var.private_dns_zone_ids) == 0 || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_ids can only be specified when private_endpoint_subnet_id is set."
    }
  }
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
  metadata              = each.value.metadata
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "default-lifecycle"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      dynamic "base_blob" {
        for_each = (var.default_cool_after_days != null || var.default_cold_after_days != null) ? [1] : []
        content {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.default_cool_after_days
          tier_to_cold_after_days_since_last_access_time_greater_than = var.default_cold_after_days
          auto_tier_to_hot_from_cool_enabled                          = var.default_cool_after_days != null ? true : null
        }
      }

      version {
        delete_after_days_since_creation = local.noncurrent_version_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = local.noncurrent_version_days
      }
    }
  }

  dynamic "rule" {
    for_each = local.containers_with_custom_lifecycle
    content {
      name    = "container-${rule.key}"
      enabled = true

      filters {
        prefix_match = ["${rule.key}/"]
        blob_types   = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_last_access_time_greater_than = rule.value.cool_after_days
          tier_to_cold_after_days_since_last_access_time_greater_than = rule.value.cold_after_days
          auto_tier_to_hot_from_cool_enabled                          = rule.value.cool_after_days != null ? true : null
          delete_after_days_since_modification_greater_than           = rule.value.delete_after_days
        }
      }
    }
  }
}
