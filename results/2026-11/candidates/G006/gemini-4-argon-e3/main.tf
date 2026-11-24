locals {
  is_production = contains(["prod", "production"], var.environment)

  resource_group_name = coalesce(var.resource_group_name, "${var.app_name}-${var.environment}")

  clean_app_name = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  clean_env_name = replace(lower(var.environment), "/[^a-z0-9]/", "")
  name_prefix    = substr("st${local.clean_app_name}${local.clean_env_name}", 0, 18)

  storage_account_name = coalesce(
    var.storage_account_name,
    "${local.name_prefix}${random_string.suffix.result}"
  )

  replication_type           = coalesce(var.replication_type, local.is_production ? "ZRS" : "LRS")
  soft_delete_retention_days = coalesce(var.soft_delete_retention_days, local.is_production ? 30 : 7)

  contributor_principal_ids = toset(concat([var.app_principal_id], tolist(var.additional_contributor_principal_ids)))

  lifecycle_rules = {
    for name, cfg in var.containers : name => {
      has_base_blob = (
        cfg.cool_tier_after_days != null ||
        cfg.cold_tier_after_days != null ||
        cfg.archive_tier_after_days != null ||
        cfg.delete_after_days != null
      )
      has_version             = var.versioning_enabled && cfg.delete_versions_after_days != null
      cool_tier_after_days    = cfg.cool_tier_after_days
      cold_tier_after_days    = cfg.cold_tier_after_days
      archive_tier_after_days = cfg.archive_tier_after_days
      delete_after_days       = cfg.delete_after_days
      delete_versions_days    = cfg.delete_versions_after_days
    }
    if(
      cfg.cool_tier_after_days != null ||
      cfg.cold_tier_after_days != null ||
      cfg.archive_tier_after_days != null ||
      cfg.delete_after_days != null ||
      (var.versioning_enabled && cfg.delete_versions_after_days != null)
    )
  }

  default_tags = {
    application = var.app_name
    environment = var.environment
    managed_by  = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true

  keepers = {
    app_name            = var.app_name
    environment         = var.environment
    resource_group_name = local.resource_group_name
  }
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = local.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  sftp_enabled                      = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = true

  blob_properties {
    versioning_enabled       = var.versioning_enabled
    change_feed_enabled      = local.is_production
    last_access_time_enabled = true

    delete_retention_policy {
      days = local.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_retention_days
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

  dynamic "network_rules" {
    for_each = var.network_rules != null ? [var.network_rules] : []
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
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
  count = length(local.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = local.lifecycle_rules
    content {
      name    = "${rule.key}-lifecycle"
      enabled = true

      filters {
        prefix_match = ["${rule.key}/"]
        blob_types   = ["blockBlob"]
      }

      actions {
        dynamic "base_blob" {
          for_each = rule.value.has_base_blob ? [rule.value] : []
          content {
            tier_to_cool_after_days_since_modification_greater_than    = base_blob.value.cool_tier_after_days
            tier_to_cold_after_days_since_modification_greater_than    = base_blob.value.cold_tier_after_days
            tier_to_archive_after_days_since_modification_greater_than = base_blob.value.archive_tier_after_days
            delete_after_days_since_modification_greater_than          = base_blob.value.delete_after_days
          }
        }

        dynamic "version" {
          for_each = rule.value.has_version ? [rule.value.delete_versions_days] : []
          content {
            delete_after_days_since_creation = version.value
          }
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
  for_each = var.additional_reader_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
