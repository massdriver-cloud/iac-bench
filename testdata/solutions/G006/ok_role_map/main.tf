data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.this.name
  location                 = coalesce(var.location, data.azurerm_resource_group.this.location)
  account_tier             = "Standard"
  account_replication_type = var.zone_redundant ? "ZRS" : "LRS"

  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = var.versioning

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

locals {
  grants = { for id in var.principal_ids : id => { principal_id = id, role = "Storage Blob Data Contributor" } }
}

resource "azurerm_role_assignment" "app" {
  for_each             = local.grants
  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

resource "azurerm_storage_management_policy" "expiry" {
  count              = var.delete_after_days == null ? 0 : 1
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.delete_after_days
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "blob-logs"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
