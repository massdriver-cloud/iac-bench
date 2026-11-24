resource "azurerm_monitor_autoscale_setting" "capacity" {
  name                = "scale-${var.service_name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  target_resource_id  = azurerm_service_plan.service.id
  profile {
    name = "cpu"
    capacity {
      default = var.capacity.minimum
      minimum = var.capacity.minimum
      maximum = var.capacity.maximum
    }
    dynamic "rule" {
      for_each = var.capacity.maximum > var.capacity.minimum ? {
        out = { direction = "Increase", operator = "GreaterThan", threshold = 70, window = "PT5M", cooldown = "PT5M" }
        in  = { direction = "Decrease", operator = "LessThan", threshold = 30, window = "PT15M", cooldown = "PT10M" }
      } : {}
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.service.id
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
  tags = var.tags
}
resource "azurerm_log_analytics_workspace" "service" {
  name                = "logs-${var.service_name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
resource "azurerm_monitor_diagnostic_setting" "service" {
  for_each                   = merge({ production = azurerm_linux_web_app.service.id }, var.candidate_image == null ? {} : { staging = azurerm_linux_web_app_slot.staging[0].id })
  name                       = "service-diagnostics"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServicePlatformLogs"])
    content { category = enabled_log.value }
  }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_metric_alert" "errors" {
  name                = "${var.service_name}-server-errors"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "At least five production HTTP server errors in five minutes. Check the service diagnostic logs."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = 5
  }
  dynamic "action" {
    for_each = var.alert_action_group_ids
    content { action_group_id = action.value }
  }
  tags = var.tags
}
