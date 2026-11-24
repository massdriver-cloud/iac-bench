locals {
  effective_resource_group_name = coalesce(var.resource_group_name, "${var.app_name}-${var.environment}")
  effective_location            = coalesce(var.location, data.azurerm_resource_group.app.location)

  is_production              = contains(["prod", "production"], lower(var.environment))
  effective_replication_type = coalesce(var.replication_type, local.is_production ? "ZRS" : "LRS")

  # Storage account names must be 3-24 characters, lowercase letters and numbers only.
  clean_app_name = substr(replace(lower(var.app_name), "/[^a-z0-9]/", ""), 0, 10)
  clean_env_name = substr(replace(lower(var.environment), "/[^a-z0-9]/", ""), 0, 6)
  storage_name   = "st${local.clean_app_name}${local.clean_env_name}${random_string.suffix.result}"

  contributor_principals = toset(concat([var.principal_id], tolist(var.additional_contributor_principal_ids)))

  tags = merge(
    data.azurerm_resource_group.app.tags,
    {
      application = var.app_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )
}

data "azurerm_resource_group" "app" {
  name = local.effective_resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "app" {
  name                     = local.storage_name
  resource_group_name      = data.azurerm_resource_group.app.name
  location                 = local.effective_location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.effective_replication_type
  access_tier              = "Hot"

  # Security and authentication hardening: enforce Entra ID RBAC, disable shared keys & local users, require TLS 1.2
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled       = var.enable_versioning
    change_feed_enabled      = true
    last_access_time_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    dynamic "cors_rule" {
      for_each = length(var.cors_allowed_origins) > 0 ? [1] : []
      content {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "HEAD", "OPTIONS", "PUT", "POST"]
        allowed_origins    = var.cors_allowed_origins
        exposed_headers    = ["x-ms-*", "content-length", "content-type", "etag"]
        max_age_in_seconds = 3600
      }
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "app" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.app.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.app.id

  rule {
    name    = "lifecycle-optimization"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = var.auto_cool_after_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = var.delete_old_versions_after_days
      }

      version {
        delete_after_days_since_creation = var.delete_old_versions_after_days
      }
    }
  }
}

resource "azurerm_role_assignment" "blob_contributor" {
  for_each = local.contributor_principals

  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_reader" {
  for_each = var.additional_reader_principal_ids

  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "blob_delegator" {
  for_each = local.contributor_principals

  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = each.value
}
