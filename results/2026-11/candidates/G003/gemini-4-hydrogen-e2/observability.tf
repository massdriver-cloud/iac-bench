resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = "log-${local.name_prefix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count = local.create_app_insights ? 1 : 0

  name                = "appi-${local.name_prefix}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.log_retention_days
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count = local.has_log_analytics ? 1 : 0

  name                       = "diag-app-${local.name_prefix}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = [
      "AppServiceHTTPLogs",
      "AppServiceConsoleLogs",
      "AppServiceAppLogs",
      "AppServicePlatformLogs",
      "AppServiceAuditLogs",
      "AppServiceIPSecAuditLogs",
    ]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = local.has_log_analytics && local.staging_slot_enabled ? 1 : 0

  name                       = "diag-slot-${local.name_prefix}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = [
      "AppServiceHTTPLogs",
      "AppServiceConsoleLogs",
      "AppServiceAppLogs",
      "AppServicePlatformLogs",
    ]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count = local.has_log_analytics && local.create_service_plan ? 1 : 0

  name                       = "diag-asp-${local.name_prefix}"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "this" {
  count = local.create_action_group ? 1 : 0

  name                = "ag-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace("ag${var.service_name}", "-", ""), 0, 12)
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = toset(var.observability.alert_emails)
    content {
      name                    = "sre-${substr(md5(email_receiver.value), 0, 8)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.observability.enabled && var.observability.alerts_enabled ? 1 : 0

  name                = "alert-5xx-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when HTTP 5xx server errors exceed ${var.observability.alert_thresholds.http_5xx_count} in 5 minutes."
  severity            = 2
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
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "high_latency" {
  count = var.observability.enabled && var.observability.alerts_enabled ? 1 : 0

  name                = "alert-latency-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Alert when average HTTP response time exceeds ${var.observability.alert_thresholds.response_time_seconds}s over 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.response_time_seconds
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.observability.enabled && var.observability.alerts_enabled && var.health.path != null ? 1 : 0

  name                = "alert-health-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Critical alert when App Service Health Check status drops below 100%."
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
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = var.observability.enabled && var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-cpu-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Alert when App Service Plan average CPU exceeds ${var.observability.alert_thresholds.cpu_percent}% for 15 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.cpu_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = var.observability.enabled && var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-mem-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Alert when App Service Plan average memory exceeds ${var.observability.alert_thresholds.memory_percent}% for 15 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.memory_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
