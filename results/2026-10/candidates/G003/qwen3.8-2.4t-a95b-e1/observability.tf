# -----------------------------------------------------------------------------
# Observability: App Insights for APM, Log Analytics for platform logs and
# metrics, wired together and injected into the app by default.
# -----------------------------------------------------------------------------

locals {
  diagnostic_log_categories = [
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceHTTPLogs",
    "AppServicePlatformLogs",
  ]
}

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-ai"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  application_type  = "web"
  workspace_id      = local.law_workspace_id
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# Stream app/platform logs and all metrics into Log Analytics.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name               = "${var.name}-diag"
  target_resource_id = azurerm_linux_web_app.this.id

  log_analytics_workspace_id = local.law_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_log_categories

    content {
      category = enabled_log.value

      retention_policy {
        enabled = true
        days    = var.log_retention_days
      }
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = true
      days    = var.log_retention_days
    }
  }
}
