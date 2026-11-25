locals {
  cpu_scale_rules = {
    out = { operator = "GreaterThan", threshold = 70, direction = "Increase", window = "PT5M", cooldown = "PT5M" }
    in  = { operator = "LessThan", threshold = 30, direction = "Decrease", window = "PT15M", cooldown = "PT10M" }
  }
}

resource "azurerm_monitor_autoscale_setting" "service" {
  name                = "${var.name}-workers"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  target_resource_id  = azurerm_service_plan.service.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "steady-state"

    capacity {
      default = var.capacity.minimum
      minimum = var.capacity.minimum
      maximum = var.capacity.maximum
    }

    dynamic "rule" {
      for_each = var.capacity.minimum < var.capacity.maximum ? local.cpu_scale_rules : {}
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_namespace   = "Microsoft.Web/serverfarms"
          metric_resource_id = azurerm_service_plan.service.id
          operator           = rule.value.operator
          threshold          = rule.value.threshold
          statistic          = "Average"
          time_aggregation   = "Average"
          time_grain         = "PT1M"
          time_window        = rule.value.window
        }

        scale_action {
          direction = rule.value.direction
          type      = "ChangeCount"
          value     = 1
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}

resource "azurerm_log_analytics_workspace" "service" {
  name                = "law-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "service" {
  name                = "appi-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "web" {
  for_each = merge(
    { production = azurerm_linux_web_app.service.id },
    { for slot in azurerm_linux_web_app_slot.staging : "staging" => slot.id }
  )

  name                           = "app-service-to-workspace"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.service.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServicePlatformLogs"])
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  count               = length(var.action_group_ids) == 0 ? 0 : 1
  name                = "${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = "Production has at least 10 HTTP 5xx responses over five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = 10
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
