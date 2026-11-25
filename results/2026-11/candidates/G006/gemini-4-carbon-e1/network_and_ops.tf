# Optional Private Endpoint for Blob Storage (Private Link from AKS / App Service VNet)
resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

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

  tags = local.tags
}

# Optional Storage Account-level capacity & transaction metrics
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.storage_account_name}-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "Capacity"
  }

  enabled_metric {
    category = "Transaction"
  }
}

# Optional Blob Service-level audit logs (StorageRead, StorageWrite, StorageDelete) & metrics
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

# Production deletion guard (enabled automatically in prod unless overridden)
resource "azurerm_management_lock" "cannot_delete" {
  count = local.enable_delete_lock ? 1 : 0

  name       = "lock-${local.storage_account_name}-cannotdelete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects ${var.app_name} (${var.environment}) application files from accidental storage account deletion."
}
