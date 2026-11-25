resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                       = "central-logs"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.staging_enabled ? 1 : 0
  name                       = "central-logs"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "${var.name}-capacity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "steady-state"
    capacity {
      default = tostring(var.capacity.default_instances)
      minimum = tostring(var.capacity.autoscale_enabled ? var.capacity.min_instances : var.capacity.default_instances)
      maximum = tostring(var.capacity.autoscale_enabled ? var.capacity.max_instances : var.capacity.default_instances)
    }

    dynamic "rule" {
      for_each = var.capacity.autoscale_enabled ? {
        out = { operator = "GreaterThan", threshold = 70, direction = "Increase", window = "PT5M", cooldown = "PT5M" }
        in  = { operator = "LessThan", threshold = 30, direction = "Decrease", window = "PT10M", cooldown = "PT10M" }
      } : {}
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = rule.value.window
          time_aggregation   = "Average"
          operator           = rule.value.operator
          threshold          = rule.value.threshold
        }
        scale_action {
          direction = rule.value.direction
          type      = "ChangeCount"
          value     = "1"
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}

resource "azurerm_monitor_action_group" "this" {
  name                = "${var.name}-oncall"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "sre-oncall"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${substr(sha256(email_receiver.value), 0, 12)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = {
    server_errors = { metric = "Http5xx", aggregation = "Total", operator = "GreaterThanOrEqual", threshold = 10, severity = 1, description = "At least 10 HTTP 5xx responses in five minutes. Inspect application logs and recent deployments." }
    unhealthy     = { metric = "HealthCheckStatus", aggregation = "Average", operator = "LessThan", threshold = 100, severity = 1, description = "One or more workers failing readiness checks. Inspect health endpoint and dependencies." }
    latency       = { metric = "HttpResponseTime", aggregation = "Average", operator = "GreaterThan", threshold = 2, severity = 2, description = "Average response time exceeds two seconds for five minutes. Inspect dependencies and capacity." }
  }
  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = length(var.alert_email_addresses) > 0 ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }
}
