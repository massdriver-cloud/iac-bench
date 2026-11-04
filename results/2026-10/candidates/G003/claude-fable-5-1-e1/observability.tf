############################################
# Log Analytics (create or bring your own)
############################################

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name}-law"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

locals {
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  web_app_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
  ]

  alerts_enabled  = var.alerts.enabled
  action_group_id = var.alerts.enabled ? coalesce(var.alerts.action_group_id, try(azurerm_monitor_action_group.this[0].id, null)) : null

  alert_frequency = "PT${var.alerts.evaluation_frequency_minutes}M"
  alert_window    = "PT${var.alerts.window_minutes}M"
}

############################################
# Application Insights (workspace-based)
############################################

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-appi"
  resource_group_name = local.resource_group_name
  location            = var.location
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id
  tags                = local.tags
}

############################################
# Diagnostic settings -> Log Analytics
############################################

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "${var.name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.web_app_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "${var.name}-plan-diag"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

############################################
# Action group
############################################

resource "azurerm_monitor_action_group" "this" {
  count = local.alerts_enabled && var.alerts.action_group_id == null ? 1 : 0

  name                = "${var.name}-ag"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alerts.email_addresses
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

############################################
# Standard alert pack
############################################

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Server errors (HTTP 5xx) exceeded ${var.alerts.http_5xx_count_per_5m} in the evaluation window."
  severity            = 1
  frequency           = local.alert_frequency
  window_size         = local.alert_window
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alerts.http_5xx_count_per_5m
  }

  action {
    action_group_id = local.action_group_id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time exceeded ${var.alerts.response_time_seconds}s."
  severity            = 2
  frequency           = local.alert_frequency
  window_size         = local.alert_window
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.response_time_seconds
  }

  action {
    action_group_id = local.action_group_id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "One or more instances are failing the health check at ${var.health_check_path}."
  severity            = 1
  frequency           = local.alert_frequency
  window_size         = local.alert_window
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = local.action_group_id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-plan-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "App Service Plan CPU above ${var.alerts.cpu_percent}% (saturation, or autoscale at max)."
  severity            = 2
  frequency           = local.alert_frequency
  window_size         = local.alert_window
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.cpu_percent
  }

  action {
    action_group_id = local.action_group_id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = local.alerts_enabled ? 1 : 0

  name                = "${var.name}-plan-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "App Service Plan memory above ${var.alerts.memory_percent}%."
  severity            = 2
  frequency           = local.alert_frequency
  window_size         = local.alert_window
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.memory_percent
  }

  action {
    action_group_id = local.action_group_id
  }

  tags = local.tags
}
