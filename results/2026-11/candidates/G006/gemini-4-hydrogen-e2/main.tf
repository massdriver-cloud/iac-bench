locals {
  is_prod = var.environment == "prod"

  sanitized_app = replace(lower(var.application_name), "/[^a-z0-9]/", "")
  sanitized_env = replace(lower(var.environment), "/[^a-z0-9]/", "")
  name_hash     = substr(sha256("${var.resource_group_name}/${var.application_name}/${var.environment}/${var.location}"), 0, 6)

  derived_storage_account_name = substr(
    "st${substr(local.sanitized_app, 0, 10)}${substr(local.sanitized_env, 0, 6)}${local.name_hash}",
    0,
    24
  )

  storage_account_name = coalesce(var.storage_account_name, local.derived_storage_account_name)
  replication_type     = coalesce(var.replication_type, local.is_prod ? "ZRS" : "LRS")
  restrict_network     = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_rules) > 0

  contributor_principals = toset(concat([var.principal_id], tolist(var.contributor_principal_ids)))
  reader_principals      = setsubtract(var.reader_principal_ids, local.contributor_principals)

  enable_base_blob_tiering = var.cool_tier_after_days > 0 || var.cold_tier_after_days > 0

  common_tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )
}

resource "azurerm_storage_account" "this" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.replication_type
  access_tier              = "Hot"

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  public_network_access_enabled     = var.public_network_access_enabled

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = local.is_prod
    last_access_time_enabled = true

    delete_retention_policy {
      days = local.is_prod ? 30 : 7
    }

    container_delete_retention_policy {
      days = local.is_prod ? 30 : 7
    }

    dynamic "restore_policy" {
      for_each = local.is_prod ? [1] : []
      content {
        days = 14
      }
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "HEAD", "OPTIONS", "POST", "PUT"]
        allowed_origins    = var.cors_allowed_origins
        exposed_headers    = ["ETag", "x-ms-request-id"]
        max_age_in_seconds = 3600
      }
    }
  }

  network_rules {
    default_action             = local.restrict_network ? "Deny" : "Allow"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = length(var.allowed_subnet_ids) > 0 ? var.allowed_subnet_ids : null
    ip_rules                   = length(var.allowed_ip_rules) > 0 ? var.allowed_ip_rules : null
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  lifecycle {
    precondition {
      condition     = var.cool_tier_after_days == 0 || var.cold_tier_after_days == 0 || var.cold_tier_after_days > var.cool_tier_after_days
      error_message = "When both cool_tier_after_days and cold_tier_after_days are enabled (> 0), cold_tier_after_days must be greater than cool_tier_after_days."
    }
  }

  rule {
    name    = "lifecycle-cost-and-version-hygiene"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      dynamic "base_blob" {
        for_each = local.enable_base_blob_tiering ? [1] : []
        content {
          tier_to_cool_after_days_since_last_access_time_greater_than = var.cool_tier_after_days > 0 ? var.cool_tier_after_days : null
          tier_to_cold_after_days_since_last_access_time_greater_than = var.cold_tier_after_days > 0 ? var.cold_tier_after_days : null
          auto_tier_to_hot_from_cool_enabled                          = var.cool_tier_after_days > 0 ? true : null
        }
      }

      version {
        delete_after_days_since_creation = 90
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }
}

resource "azurerm_role_assignment" "blob_contributor" {
  for_each = local.contributor_principals

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_reader" {
  for_each = local.reader_principals

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}
