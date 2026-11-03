# ---------------------------------------------------------------------------
# Observability: Application Insights and diagnostics.
# ---------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  count = var.app_insights_enabled ? 1 : 0

  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  application_type    = "web"
  tags                = var.tags
}

# App Service platform metrics/logs and app logs via diagnostic settings.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}