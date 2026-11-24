# Optional Azure Monitor diagnostic settings for audit logging and metrics.
# Activated automatically when log_analytics_workspace_id is provided.

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.storage_account_name}-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob_service" {
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

  enabled_metric {
    category = "Capacity"
  }
}
