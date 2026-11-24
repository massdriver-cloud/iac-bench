resource "azurerm_monitor_autoscale_setting" "capacity" {
  name                = "${var.name}-workers"
  resource_group_name = local.rg
  location            = local.region
  target_resource_id  = azurerm_service_plan.service.id
  tags                = var.tags
  profile {
    name = "baseline"
    capacity {
      default = var.capacity.min
      minimum = var.capacity.min
      maximum = var.capacity.max
    }
    dynamic "rule" {
      for_each = { Increase = { threshold = 70, op = "GreaterThan", window = "PT5M", cooldown = "PT5M" }, Decrease = { threshold = 30, op = "LessThan", window = "PT15M", cooldown = "PT10M" } }
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.service.id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = rule.value.window
          time_aggregation   = "Average"
          operator           = rule.value.op
          threshold          = rule.value.threshold
        }
        scale_action {
          direction = rule.key
          type      = "ChangeCount"
          value     = "1"
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}
resource "azurerm_log_analytics_workspace" "service" {
  name                = "${var.name}-logs"
  location            = local.region
  resource_group_name = local.rg
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
resource "azurerm_application_insights" "service" {
  name                = "${var.name}-insights"
  location            = local.region
  resource_group_name = local.rg
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = var.tags
}
resource "azurerm_monitor_diagnostic_setting" "service" {
  for_each                   = merge({ production = azurerm_linux_web_app.service.id }, var.staging_image == null ? {} : { staging = azurerm_linux_web_app_slot.staging[0].id })
  name                       = "service-logs"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}
resource "azurerm_monitor_metric_alert" "errors" {
  name                = "${var.name}-server-errors"
  resource_group_name = local.rg
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "Five or more production HTTP 5xx responses in five minutes."
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
    for_each = var.action_group_ids
    content { action_group_id = action.value }
  }
  tags = var.tags
}
