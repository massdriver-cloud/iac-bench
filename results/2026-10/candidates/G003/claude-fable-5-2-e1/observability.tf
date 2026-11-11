# ---------------------------------------------------------------------------------------------
# Logs and traces
# ---------------------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = var.observability.log_analytics_workspace_id == null ? 1 : 0

  name                = "log-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.tags
}

locals {
  log_analytics_workspace_id = var.observability.log_analytics_workspace_id != null ? var.observability.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  site_log_categories = [
    "AppServiceHTTPLogs",       # access log
    "AppServiceConsoleLogs",    # container stdout / stderr
    "AppServiceAppLogs",        # application logs
    "AppServicePlatformLogs",   # container lifecycle: pulls, starts, crashes, health evictions
    "AppServiceAuditLogs",      # publishing / SCM logins
    "AppServiceIPSecAuditLogs", # requests rejected by access restrictions
  ]
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  application_type    = "web"
  workspace_id        = local.log_analytics_workspace_id
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.site_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# The staging slot is where a failing release shows its symptoms, so its logs matter most.
resource "azurerm_monitor_diagnostic_setting" "staging" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app_slot.staging.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.site_log_categories

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------------------------

locals {
  metric_alerts = var.alerts.enabled ? {
    http-5xx = {
      description = "${var.name}: more than ${var.alerts.http_5xx_count} HTTP 5xx responses in 5 minutes."
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.alerts.http_5xx_count
      severity    = 1
      frequency   = "PT1M"
      window      = "PT5M"
    }
    unhealthy-instances = {
      description = "${var.name}: at least one instance has been failing ${var.health_check_path} for 5 minutes."
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 100
      severity    = 1
      frequency   = "PT1M"
      window      = "PT5M"
    }
    response-time = {
      description = "${var.name}: average response time above ${var.alerts.response_time_seconds}s for 15 minutes."
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alerts.response_time_seconds
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
    }
    plan-cpu = {
      description = "${var.name}: plan CPU above ${var.alerts.saturation_percent}% for 15 minutes - autoscale is not keeping up or is at max_instances."
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "CpuPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alerts.saturation_percent
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
    }
    plan-memory = {
      description = "${var.name}: plan memory above ${var.alerts.saturation_percent}% for 15 minutes - autoscale is not keeping up or is at max_instances."
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "MemoryPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alerts.saturation_percent
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
    }
  } : {}
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = local.metric_alerts

  name                = "alert-${var.name}-${each.key}"
  resource_group_name = local.resource_group_name
  description         = each.value.description
  scopes              = [each.value.scope]
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = toset(var.alerts.action_group_ids)

    content {
      action_group_id = action.value
    }
  }
}
