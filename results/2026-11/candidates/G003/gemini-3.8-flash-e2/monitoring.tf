# -----------------------------------------------------------------------------
# Observability: Diagnostic Settings (Log Analytics Workspace)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${var.app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "slot" {
  count                      = var.log_analytics_workspace_id != null && var.staging_slot_enabled ? 1 : 0
  name                       = "diag-${var.app_name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  count                      = var.log_analytics_workspace_id != null && var.service_plan_id == null ? 1 : 0
  name                       = "diag-plan-${var.app_name}"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Observability: SRE Metric Alerts
# -----------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.alerts_enabled ? 1 : 0
  name                = "alert-${var.app_name}-http5xx"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when HTTP 5xx server errors exceed threshold over 5 minutes."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

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

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.alerts_enabled ? 1 : 0
  name                = "alert-${var.app_name}-latency"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when average HTTP response time exceeds threshold in seconds over 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_threshold_seconds
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.alerts_enabled && var.health_check_path != null ? 1 : 0
  name                = "alert-${var.app_name}-healthcheck"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Triggers when App Service Health Check percentage drops below threshold (instances failing health check)."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.alert_health_check_threshold
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "cpu_plan" {
  count               = var.alerts_enabled ? 1 : 0
  name                = "alert-${var.app_name}-plan-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [local.service_plan_id]
  description         = "Triggers when App Service Plan average CPU utilization exceeds threshold over 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
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

  tags = local.tags
}
