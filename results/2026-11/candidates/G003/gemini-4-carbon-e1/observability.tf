# -----------------------------------------------------------------------------
# Log Analytics Workspace & Workspace-Based Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = local.log_analytics_name
  location            = local.location
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_in_days
  daily_quota_gb      = var.observability.log_daily_quota_gb
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count = local.create_app_insights ? 1 : 0

  name                = local.app_insights_name
  location            = local.location
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.application_insights_retention_in_days
  sampling_percentage = var.observability.application_insights_sampling_percentage
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Diagnostic Telemetry Streaming (Logs, Container Stdout/Stderr & Metrics)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "diag-${local.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.web_app_diagnostic_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = var.rollout.staging_slot_enabled ? 1 : 0

  name                       = "diag-${local.web_app_name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.web_app_diagnostic_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count = local.create_service_plan ? 1 : 0

  name                       = "diag-${local.service_plan_name}"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Golden-Signal SRE Metric Alerts
# -----------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${var.service_name}-${var.environment}-http-5xx"
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Elevated HTTP 5xx server error volume on ${var.service_name} (${var.environment})."
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
    for_each = toset(var.observability.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_latency" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${var.service_name}-${var.environment}-latency"
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response time exceeded ${var.observability.response_time_seconds_threshold}s on ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.response_time_seconds_threshold
  }

  dynamic "action" {
    for_each = toset(var.observability.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${var.service_name}-${var.environment}-health"
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service load-balancer health check status degraded below ${var.observability.health_check_status_threshold}% on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.health_check_status_threshold
  }

  dynamic "action" {
    for_each = toset(var.observability.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu_saturation" {
  count = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-${var.service_name}-${var.environment}-plan-cpu"
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained CPU saturation above ${var.observability.cpu_percentage_alert_threshold}% on App Service Plan ${local.service_plan_name}."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.cpu_percentage_alert_threshold
  }

  dynamic "action" {
    for_each = toset(var.observability.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "memory_saturation" {
  count = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-${var.service_name}-${var.environment}-plan-memory"
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained memory saturation above ${var.observability.memory_percentage_alert_threshold}% on App Service Plan ${local.service_plan_name}."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.memory_percentage_alert_threshold
  }

  dynamic "action" {
    for_each = toset(var.observability.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}
