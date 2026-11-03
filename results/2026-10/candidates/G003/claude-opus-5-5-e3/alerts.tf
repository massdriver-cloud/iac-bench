resource "azurerm_monitor_action_group" "this" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ag-${local.base_name}"
  resource_group_name = local.resource_group_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

locals {
  metric_alerts = {
    http5xx = {
      description = "HTTP 5xx responses above threshold"
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.alert_http_5xx_threshold
      severity    = 1
    }
    response_time = {
      description = "Average HTTP response time above threshold"
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_response_time_seconds
      severity    = 2
    }
    health_check = {
      description = "Instances failing health checks"
      scope       = azurerm_linux_web_app.this.id
      namespace   = "Microsoft.Web/sites"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 100
      severity    = 1
    }
    plan_cpu = {
      description = "Plan CPU saturated (autoscale may be at max)"
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "CpuPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
    }
    plan_memory = {
      description = "Plan memory saturated"
      scope       = azurerm_service_plan.this.id
      namespace   = "Microsoft.Web/serverfarms"
      metric      = "MemoryPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each            = local.metric_alerts
  name                = "alert-${local.base_name}-${each.key}"
  resource_group_name = local.resource_group_name
  scopes              = [each.value.scope]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.this
    content {
      action_group_id = action.value.id
    }
  }
}
