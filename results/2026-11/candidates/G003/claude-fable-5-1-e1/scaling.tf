############################################
# Capacity: always managed via an autoscale setting on Standard+ SKUs.
#   - fixed capacity when capacity.min == capacity.max (no rules)
#   - CPU-driven scale out/in between min and max otherwise
############################################

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_supported ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true

  profile {
    name = "default"

    capacity {
      default = var.capacity.min
      minimum = var.capacity.min
      maximum = var.capacity.max
    }

    # Scale out: +1 instance when 5-min average CPU is above the threshold.
    dynamic "rule" {
      for_each = local.autoscale_dynamic ? [1] : []
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          metric_namespace   = "Microsoft.Web/serverfarms"
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = "PT5M"
          time_aggregation   = "Average"
          operator           = "GreaterThan"
          threshold          = var.capacity.scale_out_cpu_percent
        }
        scale_action {
          direction = "Increase"
          type      = "ChangeCount"
          value     = "1"
          cooldown  = "PT5M"
        }
      }
    }

    # Scale in: -1 instance when 10-min average CPU is below the threshold.
    # Longer window + cooldown than scale-out so capacity is shed conservatively.
    dynamic "rule" {
      for_each = local.autoscale_dynamic ? [1] : []
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          metric_namespace   = "Microsoft.Web/serverfarms"
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = "PT10M"
          time_aggregation   = "Average"
          operator           = "LessThan"
          threshold          = var.capacity.scale_in_cpu_percent
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

  dynamic "notification" {
    for_each = length(var.alerts.email_addresses) > 0 ? [1] : []
    content {
      email {
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
        custom_emails                         = var.alerts.email_addresses
      }
    }
  }

  tags = local.tags
}
