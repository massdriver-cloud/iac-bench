resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = "log-${local.name_prefix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_application_insights" "this" {
  count = local.create_app_insights ? 1 : 0

  name                = "appi-${local.name_prefix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.this]
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count = local.create_diagnostics ? 1 : 0

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
  count = local.create_diagnostics && local.enable_staging_slot ? 1 : 0

  name                       = "diag-${local.name_prefix}-staging"
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
  count = local.create_alerts ? 1 : 0

  name                = "alert-${local.name_prefix}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when ${var.service_name} (${var.environment}) emits HTTP 5xx server errors."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.http_5xx_count
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "latency" {
  count = local.create_alerts ? 1 : 0

  name                = "alert-${local.name_prefix}-high-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when ${var.service_name} (${var.environment}) average response time exceeds threshold."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.latency_seconds
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = local.create_alerts && var.health_check.path != null ? 1 : 0

  name                = "alert-${local.name_prefix}-health-degraded"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when ${var.service_name} (${var.environment}) health probe drops below 100% healthy."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = local.create_alerts && local.create_service_plan ? 1 : 0

  name                = "alert-${local.name_prefix}-plan-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Alert when ${var.service_name} (${var.environment}) App Service Plan CPU saturates."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.cpu_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = local.create_alerts && local.create_service_plan ? 1 : 0

  name                = "alert-${local.name_prefix}-plan-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Alert when ${var.service_name} (${var.environment}) App Service Plan memory saturates."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.memory_percent
  }

  dynamic "action" {
    for_each = var.observability.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
