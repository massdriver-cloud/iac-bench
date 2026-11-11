# ---------------------------------------------------------------------------
# Observability: Log Analytics + Application Insights + availability testing
# ---------------------------------------------------------------------------

# Central store for platform and container logs.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.service_name}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days
  daily_quota_gb    = -1 # no daily cap; manage cost via retention

  tags = local.common_tags
}

# APM for the service: requests, dependencies, failures, live metrics.
#
# Deliberately a classic (non workspace-based) component: this azurerm
# provider version can only create classic availability tests
# (azurerm_application_insights_web_test), and those are not supported
# against workspace-based Application Insights. Classic components still
# expose the connection string and instrumentation key the app needs.
resource "azurerm_application_insights" "this" {
  name                = "${var.service_name}-ai"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  application_type  = "web"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Ship platform logs and all metrics into Log Analytics next to the app logs.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "${var.service_name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

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
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Availability: URL-ping test against the health endpoint from multiple
# regions, with retries. Failures surface as availability alerts in
# Application Insights; point the on-call notification pipeline (Action
# Group / alert processing rule) at the availability metric to get paged.
# ---------------------------------------------------------------------------

resource "azurerm_application_insights_web_test" "availability" {
  count = var.availability_test_enabled ? 1 : 0

  name                    = "${var.service_name}-availability"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  application_insights_id = azurerm_application_insights.this.id

  kind          = "ping"
  enabled       = true
  frequency     = var.availability_test_frequency_seconds
  timeout       = var.availability_test_timeout_seconds
  retry_enabled = true
  geo_locations = var.availability_test_locations
  configuration = local.availability_test_configuration

  tags = local.common_tags
}
