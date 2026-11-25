# Optional audit logging and metrics to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.storage_account_name}-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Transaction"
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
}

# Optional Microsoft Defender for Storage — on-upload malware scanning & sensitive data discovery
resource "azurerm_security_center_storage_defender" "this" {
  count = var.enable_defender_malware_scanning ? 1 : 0

  storage_account_id                          = azurerm_storage_account.this.id
  override_subscription_settings_enabled      = true
  malware_scanning_on_upload_enabled          = true
  malware_scanning_on_upload_cap_gb_per_month = var.defender_malware_scan_cap_gb_per_month
  sensitive_data_discovery_enabled            = true
}
