# -----------------------------------------------------------------------------
# Observability: one workspace-based pipeline per service. Everything the
# platform emits (HTTP logs, container stdout, audit and platform logs,
# metrics) lands in Log Analytics; the app's own telemetry lands in
# Application Insights, which shares the same workspace.
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_in_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  sampling_percentage = var.app_insights_sampling_percentage
  tags                = local.tags
}

# Production slot: all log categories plus platform metrics.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${local.name}-app"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  # Resource-specific tables (AppServiceHTTPLogs, AppServiceConsoleLogs, ...)
  # are far nicer to query than the legacy AzureDiagnostics table.
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# The plan: capacity and CPU metrics, so scale-out events can be correlated
# with load history.
resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                           = "diag-${local.name}-plan"
  target_resource_id             = azurerm_service_plan.this.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  enabled_metric {
    category = "AllMetrics"
  }
}

# Every deployment slot streams its own logs, so rollouts can be debugged
# before traffic reaches them.
resource "azurerm_monitor_diagnostic_setting" "slots" {
  for_each = azurerm_linux_web_app_slot.this

  name                           = "diag-${local.name}-${each.key}"
  target_resource_id             = each.value.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
