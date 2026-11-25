# =============================================================================
# Log Analytics Workspace & Application Insights
# =============================================================================

resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = local.log_analytics_name
  resource_group_name = local.resource_group_name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count = var.observability.enable_application_insights ? 1 : 0

  name                = local.app_insights_name
  resource_group_name = local.resource_group_name
  location            = local.location
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.log_retention_days
  sampling_percentage = var.observability.app_insights_sampling_percentage
  tags                = local.common_tags
}

# =============================================================================
# Platform Diagnostic Settings (Logs & Metrics -> Log Analytics)
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "webapp" {
  name                       = "diag-${local.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.webapp_diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = var.rollouts.enable_staging_slot ? 1 : 0

  name                       = "diag-${local.web_app_name}-${var.rollouts.staging_slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.webapp_diagnostic_log_categories
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

# =============================================================================
# Alert Notification Routing (Action Group)
# =============================================================================

resource "azurerm_monitor_action_group" "this" {
  count = local.create_action_group ? 1 : 0

  name                = local.action_group_name
  resource_group_name = local.resource_group_name
  short_name          = local.action_group_short
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = var.observability.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.observability.alert_webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = true
    }
  }
}

# =============================================================================
# SRE Golden-Signal Metric Alerts
# =============================================================================

# 1. Errors: HTTP 5xx spike
resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.observability.enable_alerts ? 1 : 0

  name                = "alert-${local.base_name}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx server error count exceeded ${var.observability.alert_thresholds.http_5xx_count} in 5 minutes on ${var.service_name} (${var.environment})."
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
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 2. Latency: Elevated average response time
resource "azurerm_monitor_metric_alert" "high_latency" {
  count = var.observability.enable_alerts ? 1 : 0

  name                = "alert-${local.base_name}-high-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response time exceeded ${var.observability.alert_thresholds.avg_response_time_sec}s over 5 minutes on ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "AverageResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.avg_response_time_sec
  }

  dynamic "action" {
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 3. Availability / Health: Health check degradation
resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.observability.enable_alerts ? 1 : 0

  name                = "alert-${local.base_name}-health-degraded"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service health check (${var.health.path}) dropped below ${var.observability.alert_thresholds.health_check_min_pct}% on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alert_thresholds.health_check_min_pct
  }

  dynamic "action" {
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 4. Saturation: Service Plan CPU
resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = var.observability.enable_alerts && local.create_service_plan ? 1 : 0

  name                = "alert-${local.base_name}-cpu-saturation"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan CPU utilization exceeded ${var.observability.alert_thresholds.plan_cpu_percent}% for 5 minutes on ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.plan_cpu_percent
  }

  dynamic "action" {
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# 5. Saturation: Service Plan Memory
resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = var.observability.enable_alerts && local.create_service_plan ? 1 : 0

  name                = "alert-${local.base_name}-memory-saturation"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan memory utilization exceeded ${var.observability.alert_thresholds.plan_memory_percent}% for 5 minutes on ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.plan_memory_percent
  }

  dynamic "action" {
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# =============================================================================
# Optional Synthetic Multi-Region Availability Check & Alert
# =============================================================================

resource "azurerm_application_insights_standard_web_test" "health" {
  count = var.observability.synthetic_check.enabled ? 1 : 0

  name                    = "webtest-${local.base_name}-health"
  resource_group_name     = local.resource_group_name
  location                = local.location
  application_insights_id = azurerm_application_insights.this[0].id
  geo_locations           = var.observability.synthetic_check.geo_locations
  frequency               = var.observability.synthetic_check.frequency_seconds
  timeout                 = var.observability.synthetic_check.timeout_seconds
  enabled                 = true
  retry_enabled           = true
  tags                    = local.common_tags

  request {
    url       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
    http_verb = "GET"
  }

  validation_rules {
    expected_status_code = var.observability.synthetic_check.expected_status
    ssl_check_enabled    = true
  }

  lifecycle {
    precondition {
      condition     = var.observability.enable_application_insights
      error_message = "observability.synthetic_check.enabled requires observability.enable_application_insights = true."
    }

    precondition {
      condition     = var.network.public_access_enabled
      error_message = "observability.synthetic_check.enabled requires network.public_access_enabled = true because Azure Monitor probes run from public regions."
    }
  }
}

resource "azurerm_monitor_metric_alert" "synthetic_availability" {
  count = var.observability.synthetic_check.enabled && var.observability.enable_alerts ? 1 : 0

  name                = "alert-${local.base_name}-synthetic-availability"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_application_insights_standard_web_test.health[0].id, azurerm_application_insights.this[0].id]
  description         = "Synthetic health probe (${var.health.path}) failed from multiple Azure regions on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health[0].id
    component_id          = azurerm_application_insights.this[0].id
    failed_location_count = min(2, length(var.observability.synthetic_check.geo_locations))
  }

  dynamic "action" {
    for_each = local.all_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
