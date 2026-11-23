data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  account_name = "${substr(replace(var.name, "-", ""), 0, 18)}${random_string.suffix.result}"
}

resource "azurerm_storage_account" "this" {
  name                = local.account_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  account_tier             = "Standard"
  account_replication_type = "ZRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  shared_access_key_enabled         = var.allow_shared_key_access
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  infrastructure_encryption_enabled = true
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }

    restore_policy {
      days = 14
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each              = var.containers
  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "reader" {
  for_each             = var.readers
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.key
}

resource "azurerm_role_assignment" "writer" {
  for_each             = var.writers
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.key
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "age-out"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 90
      }
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "blob-access"
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
}

resource "azurerm_security_center_storage_defender" "this" {
  count                              = var.malware_scanning ? 1 : 0
  storage_account_id                 = azurerm_storage_account.this.id
  malware_scanning_on_upload_enabled = true
}

resource "azurerm_management_lock" "this" {
  name       = "${local.account_name}-no-delete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Holds the application's files. Remove the lock before retiring the account."
}
