resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "app" {
  for_each            = local.environments
  name                = "${var.name}-${each.key}-insights"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  retention_in_days   = 30
  sampling_percentage = 100
  tags                = local.tags
}

locals {
  app_resource_ids = merge(
    { production = azurerm_linux_web_app.production.id },
    var.enable_staging_slot ? { staging = azurerm_linux_web_app_slot.staging[0].id } : {}
  )
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  for_each                       = local.app_resource_ids
  name                           = "central-logs"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"
  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "sre" {
  name                = "${var.name}-sre"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "sre-alerts"
  tags                = local.tags
  dynamic "email_receiver" {
    for_each = { for index, email in sort(tolist(var.alert_email_addresses)) : "sre-${index}" => email }
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "capacity" {
  name                = "${var.name}-capacity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "standard"
    capacity {
      default = tostring(var.capacity.minimum)
      minimum = tostring(var.capacity.minimum)
      maximum = tostring(var.capacity.maximum)
    }

    # Either CPU or memory pressure scales out. Both must be low to scale in.
    dynamic "rule" {
      for_each = {
        cpu_out    = { metric = "CpuPercentage", operator = "GreaterThan", threshold = 70, window = "PT5M", direction = "Increase", cooldown = "PT5M" }
        memory_out = { metric = "MemoryPercentage", operator = "GreaterThan", threshold = 80, window = "PT5M", direction = "Increase", cooldown = "PT5M" }
        cpu_in     = { metric = "CpuPercentage", operator = "LessThan", threshold = 30, window = "PT15M", direction = "Decrease", cooldown = "PT10M" }
        memory_in  = { metric = "MemoryPercentage", operator = "LessThan", threshold = 60, window = "PT15M", direction = "Decrease", cooldown = "PT10M" }
      }
      content {
        metric_trigger {
          metric_name        = rule.value.metric
          metric_namespace   = "Microsoft.Web/serverfarms"
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

  notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = sort(tolist(var.alert_email_addresses))
    }
  }
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  name                = "${var.name}-http-5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.production.id]
  description         = "Production returned more than five HTTP 5xx responses in five minutes. Check requests, container logs and recent releases."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.tags
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

resource "azurerm_monitor_metric_alert" "saturation" {
  for_each            = toset(["CpuPercentage", "MemoryPercentage"])
  name                = "${var.name}-${lower(each.key)}-high"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan ${each.key} exceeded 90% for 15 minutes. Check autoscale ceiling, worker size, and staging load."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  auto_mitigate       = true
  tags                = local.tags
  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = each.key
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}
