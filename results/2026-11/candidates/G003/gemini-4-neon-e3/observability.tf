# ------------------------------------------------------------------------------
# Log Analytics Workspace & Application Insights
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = var.observability.enabled && var.observability.existing_log_analytics_workspace_id == null ? 1 : 0

  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count = var.observability.enabled ? 1 : 0

  name                = local.app_insights_name
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.log_analytics_workspace_id
  application_type    = "web"
  retention_in_days   = var.observability.log_retention_days
  sampling_percentage = var.observability.sampling_percentage
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# Diagnostic Settings (Web App, Staging Slot, App Service Plan)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  count = var.observability.enabled ? 1 : 0

  name                       = "diag-${local.name_base}-app"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

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
  count = var.observability.enabled && var.rollout.staging_slot_enabled ? 1 : 0

  name                       = "diag-${local.name_base}-${var.rollout.staging_slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

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

resource "azurerm_monitor_diagnostic_setting" "service_plan" {
  count = var.observability.enabled && local.manage_service_plan ? 1 : 0

  name                       = "diag-${local.name_base}-plan"
  target_resource_id         = azurerm_service_plan.this[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ------------------------------------------------------------------------------
# Synthetic Availability Monitoring (Multi-Region Standard Web Test)
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_standard_web_test" "this" {
  count = local.synthetic_probe_enabled ? 1 : 0

  name                    = local.synthetic_web_test_name
  resource_group_name     = local.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this[0].id
  geo_locations           = var.health.synthetic_probe.geo_locations
  frequency               = var.health.synthetic_probe.frequency_seconds
  timeout                 = var.health.synthetic_probe.timeout_seconds
  enabled                 = true
  retry_enabled           = true
  description             = "Synthetic health and TLS check for ${var.service_name} (${var.environment})."
  tags                    = local.common_tags

  request {
    url                              = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = var.health.synthetic_probe.expected_status_code
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = var.health.synthetic_probe.ssl_cert_remaining_days
  }
}

# ------------------------------------------------------------------------------
# Alert Action Group
# ------------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  count = local.create_action_group ? 1 : 0

  name                = local.action_group_name
  resource_group_name = local.resource_group_name
  short_name          = local.action_group_short_name
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = var.observability.alerts.email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.observability.alerts.webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = true
    }
  }
}

# ------------------------------------------------------------------------------
# SRE Golden-Signal Metric Alerts
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count = local.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_base}-http-5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx server errors exceeded ${var.observability.alerts.http_5xx_threshold} over 5 minutes."
  severity            = 1
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
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "high_latency" {
  count = local.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_base}-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average HTTP response time exceeded ${var.observability.alerts.latency_threshold_seconds}s over 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.latency_threshold_seconds
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  count = local.alerts_enabled ? 1 : 0

  name                = "alert-${local.name_base}-health-check"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "One or more App Service instances failed health checks on ${var.health.path}."
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
  count = local.alerts_enabled && local.manage_service_plan ? 1 : 0

  name                = "alert-${local.name_base}-plan-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan average CPU utilization exceeded ${var.observability.alerts.cpu_threshold_percent}%."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.cpu_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = local.alerts_enabled && local.manage_service_plan ? 1 : 0

  name                = "alert-${local.name_base}-plan-memory"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this[0].id]
  description         = "App Service Plan average memory utilization exceeded ${var.observability.alerts.memory_threshold_percent}%."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.observability.alerts.memory_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "synthetic_availability" {
  count = local.alerts_enabled && local.synthetic_probe_enabled ? 1 : 0

  name                = "alert-${local.name_base}-availability"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_application_insights.this[0].id]
  description         = "Synthetic multi-region availability dropped below ${var.observability.alerts.availability_threshold_percent}%."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.observability.alerts.availability_threshold_percent

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
