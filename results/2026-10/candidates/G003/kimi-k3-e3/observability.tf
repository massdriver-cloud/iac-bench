# Observability: a Log Analytics workspace (ours or the caller's), workspace-
# backed Application Insights wired into the app via its connection string,
# and diagnostic settings streaming app + plan telemetry to the workspace.

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceAuditEvents"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Plan-level metrics (CPU, memory, instance counts) - the autoscale signal
# and the first place to look during capacity reviews.
resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "${var.name}-plan-diag"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}
