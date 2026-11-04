########################################
# Autoscale (plan CPU driven)
########################################

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale != null ? 1 : 0

  name                = "${var.name}-autoscale"
  location            = var.location
  resource_group_name = local.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      minimum = var.instance_count
      default = var.instance_count
      maximum = var.autoscale.max_instances
    }

    # Scale out quickly on sustained CPU pressure.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        metric_namespace   = "microsoft.web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.scale_out_cpu_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in slowly to avoid flapping.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        metric_namespace   = "microsoft.web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.scale_in_cpu_percent
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
