resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = "log-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_application_insights" "this" {
  count = var.observability.app_insights_enabled ? 1 : 0

  name                = "appi-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  location            = var.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  sampling_percentage = var.observability.app_insights_sampling_pct
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count = var.observability.diagnostic_logs_enabled ? 1 : 0

  name                       = "diag-${local.name_prefix}"
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
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = var.observability.diagnostic_logs_enabled && local.effective_slots ? 1 : 0

  name                       = "diag-${local.name_prefix}-${var.rollout.staging_slot_name}"
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
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_prefix}-http5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when HTTP 5xx server error count exceeds threshold."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.http_5xx_threshold
  }

  dynamic "action" {
    for_each = var.observability.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_prefix}-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when average HTTP response time exceeds threshold."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.response_time_threshold_sec
  }

  dynamic "action" {
    for_each = var.observability.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_prefix}-health"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when App Service health check status drops below threshold."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.health_check_alert_threshold
  }

  dynamic "action" {
    for_each = var.observability.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
