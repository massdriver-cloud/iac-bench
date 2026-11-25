###############################################################################
# Logs & telemetry
###############################################################################

resource "azurerm_log_analytics_workspace" "this" {
  count = local.create_workspace ? 1 : 0

  name                = "log-${local.workload}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days
}

resource "azurerm_application_insights" "this" {
  count = var.application_insights_enabled ? 1 : 0

  name                = "appi-${local.workload}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags

  application_type = "web"
  workspace_id     = local.log_analytics_workspace_id
}

# Platform metrics are already retained by Azure Monitor (and drive the alerts
# and autoscale below), so only logs are shipped to the workspace.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.app_log_categories

    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app_slot.staging.id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = local.app_log_categories

    content {
      category = enabled_log.value
    }
  }
}

###############################################################################
# Alerts (production only)
###############################################################################

locals {
  metric_alerts = {
    http-5xx = {
      description = "HTTP 5xx responses from ${local.app_name} exceeded ${var.alerts.http_5xx_count} in 5 minutes."
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
    health-check = {
      description = "Fewer than ${var.alerts.min_healthy_percent}% of ${local.app_name} instances are passing the health check on ${var.health_check_path}."
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = var.alerts.min_healthy_percent
      severity    = 1
      frequency   = "PT1M"
      window      = "PT5M"
    }
    response-time = {
      description = "Average response time of ${local.app_name} exceeded ${var.alerts.response_time_seconds}s over 15 minutes."
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
      description = "Average CPU of plan asp-${local.workload} exceeded ${var.alerts.plan_cpu_percent}% over 15 minutes; autoscale is not keeping up or is at its ceiling."
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "CpuPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alerts.plan_cpu_percent
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
    }
    plan-memory = {
      description = "Average memory of plan asp-${local.workload} exceeded ${var.alerts.plan_memory_percent}% over 15 minutes."
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "MemoryPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alerts.plan_memory_percent
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = { for k, v in local.metric_alerts : k => v if var.alerts.enabled }

  name                = "alert-${local.workload}-${each.key}"
  resource_group_name = local.resource_group_name
  tags                = local.tags

  description   = each.value.description
  scopes        = [each.value.scope]
  severity      = each.value.severity
  frequency     = each.value.frequency
  window_size   = each.value.window
  auto_mitigate = true

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
