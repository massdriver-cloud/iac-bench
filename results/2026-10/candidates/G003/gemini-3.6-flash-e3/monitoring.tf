resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = (var.enable_diagnostic_settings && var.log_analytics_workspace_id != null) ? 1 : 0
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${var.name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when HTTP 5xx error count exceeds threshold."
  severity            = 1
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_http_5xx_threshold
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${var.name}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when average HTTP response time exceeds threshold."
  severity            = 2
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_threshold
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${var.name}-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when CPU utilization exceeds threshold."
  severity            = 2
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_cpu_threshold
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = (var.enable_alerts && var.health_check_path != null) ? 1 : 0
  name                = "alert-${var.name}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when health check status drops below 100%."
  severity            = 0
  tags                = var.tags

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
}
