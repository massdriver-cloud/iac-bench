resource "azurerm_monitor_autoscale_setting" "main" {
  count               = var.autoscale.enabled ? 1 : 0
  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = local.service_plan_id
  enabled             = true
  tags                = local.tags

  profile {
    name = "cpu"
    capacity {
      default = tostring(var.instance_count)
      minimum = tostring(var.instance_count)
      maximum = tostring(var.autoscale.max_instances)
    }
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
