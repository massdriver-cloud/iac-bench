# =============================================================================
# Optional Azure Monitor Diagnostic Settings (Blob Audit Logs & Metrics)
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${azurerm_storage_account.this.name}-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${azurerm_storage_account.this.name}-blob"
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

# =============================================================================
# Optional Microsoft Defender for Storage (On-Upload Malware Scanning)
# =============================================================================

resource "azurerm_security_center_storage_defender" "this" {
  count = var.enable_malware_scanning ? 1 : 0

  storage_account_id                          = azurerm_storage_account.this.id
  override_subscription_settings_enabled      = true
  malware_scanning_on_upload_enabled          = true
  malware_scanning_on_upload_cap_gb_per_month = var.malware_scanning_cap_gb_per_month
  sensitive_data_discovery_enabled            = true
}
