# ---------------------------------------------------------------------------
# Observability: Log Analytics + Application Insights + diagnostic settings
# ---------------------------------------------------------------------------
# Everything the SRE team needs to see what a service is doing lives in one
# workspace: platform logs, app logs, HTTP logs, audit logs and metrics.

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = local.names.log_analytics
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days

  tags = local.tags
}

# Workspace-based Application Insights: no classic standalone store, retention
# and access control follow the Log Analytics workspace.
resource "azurerm_application_insights" "this" {
  name                = local.names.app_insights
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  application_type  = "web"
  workspace_id      = local.log_analytics_workspace_id
  retention_in_days = var.log_analytics_retention_days

  tags = local.tags
}

# App logs and metrics into Log Analytics. HTTP logs are the lifeblood of
# debugging containerized APIs on App Service.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = local.names.diag_app
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Plan-level metrics (CPU, memory, HTTP queue length) power capacity reviews.
resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = local.names.diag_plan
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}
