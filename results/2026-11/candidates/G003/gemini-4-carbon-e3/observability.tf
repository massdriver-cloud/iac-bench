# -----------------------------------------------------------------------------
# Log Analytics Workspace & Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_log_analytics_workspace ? 1 : 0
  name                = "law-${local.name_prefix}"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = var.observability.log_analytics_sku
  retention_in_days   = var.observability.log_retention_days
  daily_quota_gb      = var.observability.daily_log_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  count               = var.observability.application_insights_enabled ? 1 : 0
  name                = "appi-${local.name_prefix}"
  location            = local.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.tags
}

# -----------------------------------------------------------------------------
# Multi-Region Synthetic Endpoint Availability Test (Optional)
# -----------------------------------------------------------------------------

resource "azurerm_application_insights_standard_web_test" "health" {
  count                   = var.observability.application_insights_enabled && var.health.synthetic_probe_enabled && var.network.public_network_access_enabled ? 1 : 0
  name                    = "webtest-${local.name_prefix}"
  resource_group_name     = local.resource_group_name
  location                = local.location
  application_insights_id = azurerm_application_insights.this[0].id
  geo_locations           = var.health.synthetic_probe_locations
  frequency               = var.health.synthetic_probe_frequency_sec
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  tags                    = local.tags

  request {
    url       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
    http_verb = "GET"
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }
}

# -----------------------------------------------------------------------------
# Diagnostic Settings (Structured Logs & Platform Metrics)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${local.name_prefix}-app"
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

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = local.effective_staging_slot_enabled ? 1 : 0
  name                       = "diag-${local.name_prefix}-staging"
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

resource "azurerm_monitor_diagnostic_setting" "plan" {
  count                      = local.create_service_plan ? 1 : 0
  name                       = "diag-${local.name_prefix}-plan"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Alert Notification Routing & Golden-Signal Metric Alerts
# -----------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count               = local.create_action_group ? 1 : 0
  name                = "ag-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(var.service_name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset(var.observability.alert_email_receivers)
    content {
      name                    = "email-${substr(md5(email_receiver.value), 0, 8)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = toset(var.observability.alert_webhook_uris)
    content {
      name                    = "webhook-${substr(md5(webhook_receiver.value), 0, 8)}"
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Elevated HTTP 5xx server errors on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.observability.http_5xx_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-response-time"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response latency exceeded threshold on ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.response_time_threshold_seconds
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count               = var.observability.alerts_enabled ? 1 : 0
  name                = "alert-${local.name_prefix}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service health check status degraded below ${var.observability.health_check_alert_threshold}% on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.health_check_alert_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu_saturation" {
  count               = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0
  name                = "alert-${local.name_prefix}-cpu-saturation"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained App Service Plan CPU utilization above ${var.observability.cpu_alert_threshold}% for ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "memory_saturation" {
  count               = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0
  name                = "alert-${local.name_prefix}-memory-saturation"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "Sustained App Service Plan memory utilization above ${var.observability.memory_alert_threshold}% for ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.memory_alert_threshold
  }

  dynamic "action" {
    for_each = local.effective_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
