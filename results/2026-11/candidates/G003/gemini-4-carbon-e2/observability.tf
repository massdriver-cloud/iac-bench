# -----------------------------------------------------------------------------
# Log Analytics Workspace & Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_log_analytics ? 1 : 0
  name                = local.law_name
  location            = var.location
  resource_group_name = local.effective_resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count               = local.app_insights_enabled ? 1 : 0
  name                = local.appi_name
  location            = var.location
  resource_group_name = local.effective_resource_group_name
  workspace_id        = local.log_analytics_id
  application_type    = "web"
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Platform Diagnostic Settings (Web App, Staging Slot & App Service Plan)
# -----------------------------------------------------------------------------

locals {
  web_app_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
  ]
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count                      = local.diagnostic_logs_enabled ? 1 : 0
  name                       = "diag-${local.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_id

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

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count                      = local.diagnostic_logs_enabled && local.staging_slot_enabled ? 1 : 0
  name                       = "diag-${local.web_app_name}-${var.rollout.slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_id

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

# Note: Microsoft.Web/serverfarms supports AllMetrics only (no log categories).
resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count                      = local.diagnostic_logs_enabled && local.create_service_plan ? 1 : 0
  name                       = "diag-${local.plan_name}"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Optional Dedicated Action Group & Golden-Signal Metric Alerts
# -----------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count               = local.create_action_group ? 1 : 0
  name                = local.ag_name
  resource_group_name = local.effective_resource_group_name
  short_name          = local.ag_short
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = var.observability.alert_emails
    content {
      name                    = "sre-email-${email_receiver.key + 1}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# Error Rate: HTTP 5xx spike
resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = local.alerts_enabled ? 1 : 0
  name                = substr("alert-${local.base_name}-http-5xx", 0, 128)
  resource_group_name = local.effective_resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx server error count exceeded threshold for ${var.name} (${var.environment})."
  severity            = var.observability.alerts.http_5xx_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.http_5xx_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# Latency: High average HTTP response time
resource "azurerm_monitor_metric_alert" "response_time" {
  count               = local.alerts_enabled ? 1 : 0
  name                = substr("alert-${local.base_name}-latency", 0, 128)
  resource_group_name = local.effective_resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response time exceeded ${var.observability.alerts.response_time_seconds_threshold}s for ${var.name} (${var.environment})."
  severity            = var.observability.alerts.response_time_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.response_time_seconds_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# Health: Degraded worker health probe status
resource "azurerm_monitor_metric_alert" "health_check" {
  count               = local.alerts_enabled && var.health.path != null ? 1 : 0
  name                = substr("alert-${local.base_name}-health-degraded", 0, 128)
  resource_group_name = local.effective_resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service HealthCheckStatus dropped below ${var.observability.alerts.health_check_degraded_threshold_pct}% for ${var.name} (${var.environment})."
  severity            = var.observability.alerts.health_check_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alerts.health_check_degraded_threshold_pct
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# Saturation: Sustained high CPU on App Service Plan
resource "azurerm_monitor_metric_alert" "cpu_saturation" {
  count               = local.alerts_enabled && local.create_service_plan ? 1 : 0
  name                = substr("alert-${local.base_name}-cpu-saturation", 0, 128)
  resource_group_name = local.effective_resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained App Service Plan CPU utilization exceeded ${var.observability.alerts.cpu_high_percent_threshold}% for ${var.name} (${var.environment})."
  severity            = var.observability.alerts.saturation_severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.cpu_high_percent_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# Saturation: Sustained high Memory on App Service Plan
resource "azurerm_monitor_metric_alert" "memory_saturation" {
  count               = local.alerts_enabled && local.create_service_plan ? 1 : 0
  name                = substr("alert-${local.base_name}-memory-saturation", 0, 128)
  resource_group_name = local.effective_resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained App Service Plan memory utilization exceeded ${var.observability.alerts.memory_high_percent_threshold}% for ${var.name} (${var.environment})."
  severity            = var.observability.alerts.saturation_severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.memory_high_percent_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
