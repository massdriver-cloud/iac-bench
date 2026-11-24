# ---------------------------------------------------------------------------
# Autoscale (CPU + memory on the plan)
# ---------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "this" {
  count               = local.autoscale_enabled ? 1 : 0
  name                = "autoscale-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_percent
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT20M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_percent
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Diagnostic settings -> Log Analytics
# ---------------------------------------------------------------------------
locals {
  web_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
  ]
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.workspace_id

  dynamic "enabled_log" {
    for_each = toset(local.web_log_categories)
    content {
      category = enabled_log.value
    }
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = local.workspace_id

  dynamic "enabled_log" {
    for_each = toset(local.web_log_categories)
    content {
      category = enabled_log.value
    }
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.workspace_id

  metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Baseline alerts
# ---------------------------------------------------------------------------
locals {
  app_alerts = {
    http5xx = {
      description = "HTTP 5xx responses exceeded ${var.alert_http5xx_threshold} in 5 minutes."
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.alert_http5xx_threshold
      severity    = 1
    }
    health = {
      description = "Average instance health check status dropped below 100%."
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 100
      severity    = 1
    }
    latency = {
      description = "Average response time exceeded ${var.alert_response_time_seconds}s over 5 minutes."
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_response_time_seconds
      severity    = 2
    }
  }
}

resource "azurerm_monitor_metric_alert" "app" {
  for_each            = local.app_alerts
  name                = "alert-${var.name}-${each.key}"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = toset(var.alert_action_group_ids)
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu" {
  name                = "alert-${var.name}-plan-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU above 90% for 15 minutes — autoscale is saturated or disabled."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  dynamic "action" {
    for_each = toset(var.alert_action_group_ids)
    content {
      action_group_id = action.value
    }
  }
}
