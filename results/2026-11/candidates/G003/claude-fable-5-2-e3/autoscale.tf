###############################################################################
# Capacity
#
# The autoscale setting is the single owner of the instance count. It always
# keeps the plan between min_instances and max_instances; CPU rules are only
# added when there is room to scale (max > min).
###############################################################################

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.base_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true

  profile {
    name = "default"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    # Scale out quickly ...
    dynamic "rule" {
      for_each = var.max_instances > var.min_instances ? [1] : []

      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          statistic          = "Average"
          time_grain         = "PT1M"
          time_aggregation   = "Average"
          time_window        = "PT5M"
          operator           = "GreaterThan"
          threshold          = var.scale_out_cpu_percent
        }

        scale_action {
          direction = "Increase"
          type      = "ChangeCount"
          value     = "1"
          cooldown  = "PT5M"
        }
      }
    }

    # ... and scale in conservatively.
    dynamic "rule" {
      for_each = var.max_instances > var.min_instances ? [1] : []

      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          statistic          = "Average"
          time_grain         = "PT1M"
          time_aggregation   = "Average"
          time_window        = "PT10M"
          operator           = "LessThan"
          threshold          = var.scale_in_cpu_percent
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

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.scale_in_cpu_percent + 20 <= var.scale_out_cpu_percent
      error_message = "scale_in_cpu_percent must be at least 20 points below scale_out_cpu_percent, otherwise the service will flap between instance counts."
    }
  }
}
