###############################################################################
# Capacity: Horizontal Autoscaling for App Service Plan
###############################################################################

resource "azurerm_monitor_autoscale_setting" "plan" {
  count               = var.enable_autoscaling && var.service_plan_id == null && var.capacity.max > var.capacity.min ? 1 : 0
  name                = "autoscale-${local.service_plan_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.plan[0].id

  profile {
    name = "default-autoscale-profile"

    capacity {
      default = var.capacity.default
      minimum = var.capacity.min
      maximum = var.capacity.max
    }

    # Scale Out Rule (CPU Saturation)
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_rules.cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.autoscale_rules.cooldown_minutes}M"
      }
    }

    # Scale In Rule (CPU Under-utilization)
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_rules.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.autoscale_rules.cooldown_minutes}M"
      }
    }

    # Scale Out Rule (Memory Saturation)
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_rules.memory_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.autoscale_rules.cooldown_minutes}M"
      }
    }

    # Scale In Rule (Memory Under-utilization)
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.plan[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_rules.memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.autoscale_rules.cooldown_minutes}M"
      }
    }
  }

  tags = var.tags
}
