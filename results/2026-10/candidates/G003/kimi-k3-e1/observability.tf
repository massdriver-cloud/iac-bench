# -----------------------------------------------------------------------------
# Observability: logs, metrics, APM, alerts
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  count = local.create_workspace ? 1 : 0

  name                = "law-${var.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.tags
}

resource "azurerm_application_insights" "main" {
  count = var.application_insights_enabled ? 1 : 0

  name                = "appi-${var.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id

  tags = local.tags
}

# --- diagnostic settings -------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  count = var.diagnostic_logs_enabled ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "slot" {
  count = var.diagnostic_logs_enabled && local.slot_enabled ? 1 : 0

  name                       = "diag-${var.name}-${local.slot_name}"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# The plan only emits metrics (CpuPercentage, MemoryPercentage, ...) - exactly
# what you want for capacity reviews.
resource "azurerm_monitor_diagnostic_setting" "plan" {
  count = var.diagnostic_logs_enabled ? 1 : 0

  name                       = "diag-${var.name}-plan"
  target_resource_id         = azurerm_service_plan.main.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# --- external availability test ------------------------------------------------

resource "azurerm_application_insights_standard_web_test" "main" {
  count = local.availability_test_enabled ? 1 : 0

  name                    = "avt-${var.name}"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main[0].id

  geo_locations = var.availability_test.locations
  frequency     = var.availability_test.frequency_seconds
  timeout       = var.availability_test.timeout_seconds
  retry_enabled = true
  enabled       = true

  request {
    url       = "https://${azurerm_linux_web_app.main.default_hostname}${local.health_probe_path}"
    http_verb = "GET"
  }

  validation_rules {
    expected_status_code = 200
  }

  tags = local.tags
}

# --- action groups -------------------------------------------------------------

resource "azurerm_monitor_action_group" "email" {
  count = length(var.alerts.email_receivers) > 0 ? 1 : 0

  name                = "ag-${var.name}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = substr("sre${replace(var.name, "-", "")}", 0, 12)

  dynamic "email_receiver" {
    for_each = { for idx, addr in var.alerts.email_receivers : idx => addr }
    content {
      name                    = "sre-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = local.tags
}

# --- metric alerts -------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http5xx" {
  count = var.alerts.enabled ? 1 : 0

  name                = "alert-${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Total HTTP 5xx responses of app-${var.name} exceeded ${var.alerts.http5xx_threshold} in 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alerts.http5xx_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "response_time" {
  count = var.alerts.enabled ? 1 : 0

  name                = "alert-${var.name}-slow-responses"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Average response time of app-${var.name} stayed above ${var.alerts.response_time_threshold_seconds}s for 5 minutes."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.response_time_threshold_seconds
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

# Fires when any instance starts failing the health check (100 = all healthy).
resource "azurerm_monitor_metric_alert" "health_check" {
  count = var.alerts.enabled && var.health_check_path != null ? 1 : 0

  name                = "alert-${var.name}-unhealthy-instances"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "One or more instances of app-${var.name} are failing the health check."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.alerts.health_check_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

# External availability as seen by the Application Insights standard web test.
resource "azurerm_monitor_metric_alert" "availability" {
  count = var.alerts.enabled && local.availability_test_enabled ? 1 : 0

  name                = "alert-${var.name}-availability"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main[0].id]
  description         = "External availability of app-${var.name} (standard web test against ${local.health_probe_path}) dropped below ${var.alerts.availability_threshold}%."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.alerts.availability_threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

# Plan saturation: catches the "already at max scale and still hot" case that
# autoscaling alone cannot fix.
resource "azurerm_monitor_metric_alert" "plan_cpu" {
  count = var.alerts.enabled ? 1 : 0

  name                = "alert-${var.name}-plan-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Plan CPU for asp-${var.name} stayed above ${var.alerts.cpu_threshold_percent}% for 15 minutes."
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.cpu_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "plan_memory" {
  count = var.alerts.enabled ? 1 : 0

  name                = "alert-${var.name}-plan-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_service_plan.main.id]
  description         = "Plan memory for asp-${var.name} stayed above ${var.alerts.memory_threshold_percent}% for 15 minutes."
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alerts.memory_threshold_percent
  }

  dynamic "action" {
    for_each = local.action_group_ids
    content {
      action_group_id = action.value
    }
  }

  tags = local.tags
}
