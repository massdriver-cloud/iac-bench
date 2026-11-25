resource "azurerm_monitor_autoscale_setting" "service" {
  name                = "scale-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  target_resource_id  = azurerm_service_plan.service.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "baseline"

    capacity {
      minimum = var.capacity.minimum
      default = var.capacity.default
      maximum = var.capacity.maximum
    }

    dynamic "rule" {
      for_each = var.capacity.minimum < var.capacity.maximum ? {
        out = { operator = "GreaterThan", threshold = 70, window = "PT5M", direction = "Increase", cooldown = "PT5M" }
        in  = { operator = "LessThan", threshold = 35, window = "PT15M", direction = "Decrease", cooldown = "PT10M" }
      } : {}
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.service.id
          metric_namespace   = "Microsoft.Web/serverfarms"
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

resource "azurerm_log_analytics_workspace" "service" {
  name                = "law-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "app" {
  for_each            = local.environments
  name                = "appi-${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = var.tags
}

locals {
  diagnostic_app_ids = merge(
    { production = azurerm_linux_web_app.service.id },
    var.enable_staging_slot ? { staging = azurerm_linux_web_app_slot.staging[0].id } : {}
  )
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  for_each                       = local.diagnostic_app_ids
  name                           = "service-telemetry"
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

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "service-telemetry"
  target_resource_id         = azurerm_service_plan.service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "production" {
  for_each = {
    http-5xx = { metric = "Http5xx", aggregation = "Total", operator = "GreaterThanOrEqual", threshold = 10, severity = 2, description = "Production served at least 10 HTTP 5xx responses in 5 minutes." }
    health   = { metric = "HealthCheckStatus", aggregation = "Average", operator = "LessThan", threshold = 100, severity = 1, description = "Production average worker health fell below 100% over 5 minutes." }
  }

  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.service.name
  scopes              = [azurerm_linux_web_app.service.id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
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
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
