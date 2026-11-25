# ------------------------------------------------------------------------------
# Log Analytics Workspace (Optional BYO or Dedicated)
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_log_analytics ? 1 : 0

  name                = local.log_analytics_name
  location            = local.rg_location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# Workspace-Based Application Insights (APM & Distributed Tracing)
# ------------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  count = var.observability.app_insights_enabled ? 1 : 0

  name                = local.app_insights_name
  location            = local.rg_location
  resource_group_name = local.rg_name
  workspace_id        = local.log_analytics_id
  application_type    = "web"
  retention_in_days   = var.observability.log_retention_days
  sampling_percentage = var.observability.app_insights_sampling_pct
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# Diagnostic Settings (Centralized Platform Logs & Metrics)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "diag-${local.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_id

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

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging_slot" {
  count = var.rollout.staging_slot_enabled ? 1 : 0

  name                       = "diag-${local.web_app_name}-${var.rollout.staging_slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_id

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

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count = local.create_service_plan ? 1 : 0

  name                       = "diag-${local.service_plan_name}"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ------------------------------------------------------------------------------
# Synthetic Multi-Region Availability Test & SSL Certificate Check
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_standard_web_test" "this" {
  count = local.create_availability_test ? 1 : 0

  name                    = local.web_test_name
  resource_group_name     = local.rg_name
  location                = local.rg_location
  application_insights_id = azurerm_application_insights.this[0].id
  geo_locations           = var.observability.availability_test_locations
  frequency               = var.observability.availability_test_frequency_sec
  timeout                 = var.observability.availability_test_timeout_sec
  enabled                 = true
  retry_enabled           = true
  description             = "Synthetic health and TLS probe for ${var.service_name} (${var.environment})."
  tags                    = local.common_tags

  request {
    url                              = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = var.health.expected_status_code
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = var.observability.ssl_cert_warning_days
  }
}

# ------------------------------------------------------------------------------
# Optional Alert Action Group (Email & Webhook Receivers)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count = local.create_action_group ? 1 : 0

  name                = local.action_group_name
  resource_group_name = local.rg_name
  short_name          = local.action_group_short_name
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = toset(var.observability.alert_emails)
    content {
      name                    = substr("email-${replace(email_receiver.value, "/[^a-zA-Z0-9]/", "-")}", 0, 50)
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.observability.alert_webhook_url != null ? [var.observability.alert_webhook_url] : []
    content {
      name                    = "sre-webhook"
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

# ------------------------------------------------------------------------------
# Out-of-the-Box SRE Metric Alerts (Errors, Latency, Health, Saturation, Avail)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${local.base_name}-http-5xx-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx server error count exceeded threshold on ${var.service_name} (${var.environment})."
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
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "high_latency" {
  count = var.observability.alerts_enabled ? 1 : 0

  name                = "alert-${local.base_name}-latency-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response time exceeded threshold on ${var.service_name} (${var.environment})."
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
  count = var.observability.alerts_enabled && var.health.path != null ? 1 : 0

  name                = "alert-${local.base_name}-health-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "App Service health check status degraded on ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alert_thresholds.health_check_pct
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-${local.base_name}-cpu-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan CPU saturation exceeded threshold for ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.cpu_pct
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = var.observability.alerts_enabled && local.create_service_plan ? 1 : 0

  name                = "alert-${local.base_name}-memory-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan memory saturation exceeded threshold for ${var.service_name} (${var.environment})."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alert_thresholds.memory_pct
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  count = var.observability.alerts_enabled && local.create_availability_test ? 1 : 0

  name                = "alert-${local.base_name}-availability-${local.suffix}"
  resource_group_name = local.rg_name
  scopes              = [azurerm_application_insights.this[0].id]
  description         = "Synthetic multi-region availability dropped below threshold for ${var.service_name} (${var.environment})."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alert_thresholds.availability_pct

    dimension {
      name     = "availabilityResult/name"
      operator = "Include"
      values   = [azurerm_application_insights_standard_web_test.this[0].name]
    }
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
