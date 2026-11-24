###############################################################################
# Observability: Log Analytics & Application Insights
###############################################################################

locals {
  log_analytics_workspace_id = var.enable_telemetry ? (
    var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.law[0].id
  ) : null

  app_insights_connection_string = var.enable_telemetry ? (
    var.application_insights_connection_string != null ? var.application_insights_connection_string : try(azurerm_application_insights.appi[0].connection_string, null)
  ) : null

  app_insights_instrumentation_key = var.enable_telemetry ? (
    try(azurerm_application_insights.appi[0].instrumentation_key, null)
  ) : null

  app_insights_app_id = var.enable_telemetry ? (
    try(azurerm_application_insights.appi[0].app_id, null)
  ) : null
}

resource "azurerm_log_analytics_workspace" "law" {
  count               = var.enable_telemetry && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-${local.base_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "appi" {
  count               = var.enable_telemetry && var.application_insights_connection_string == null ? 1 : 0
  name                = "appi-${local.base_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id
  tags                = var.tags
}

###############################################################################
# Observability: Diagnostic Settings (HTTP Logs, App Logs, Metrics)
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "app" {
  count                      = var.enable_telemetry ? 1 : 0
  name                       = "diag-${local.app_name}"
  target_resource_id         = azurerm_linux_web_app.app.id
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
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "slot" {
  count                      = var.enable_telemetry && var.enable_staging_slot ? 1 : 0
  name                       = "diag-${local.app_name}-${var.staging_slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
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
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

###############################################################################
# Observability: SRE Metric Alerts
###############################################################################

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-http-5xx"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.app.id]
  description         = "Triggered when container HTTP 5xx server errors exceed ${var.alert_thresholds.http_5xx_count} over 5 minutes."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.http_5xx_count
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-latency"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.app.id]
  description         = "Triggered when container average response time exceeds ${var.alert_thresholds.response_time_seconds}s over 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.response_time_seconds
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.app_name}-health-probe"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.app.id]
  description         = "Triggered when App Service health check detects unhealthy container instances (healthy percentage < 100%)."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.service_plan_name}-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [local.service_plan_id]
  description         = "Triggered when App Service Plan CPU utilization exceeds ${var.alert_thresholds.cpu_percentage}%."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.cpu_percentage
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${local.service_plan_name}-memory"
  resource_group_name = var.resource_group_name
  scopes              = [local.service_plan_id]
  description         = "Triggered when App Service Plan Memory utilization exceeds ${var.alert_thresholds.memory_percentage}%."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_thresholds.memory_percentage
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = var.tags
}
