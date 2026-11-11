# -----------------------------------------------------------------------------
# Capacity: autoscaling for the service plan. Created only when
# `capacity.max_instances > capacity.min_instances`.
#
# The rules are deliberately plain: one instance is added when average plan CPU
# or memory runs hot, one instance is removed when CPU cools off, with
# conservative cooldowns. SREs tune the thresholds, not the rule mechanics.
# -----------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "capacity"

    capacity {
      default = var.capacity.min_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.scale_out_cpu_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.scale_out_memory_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.scale_in_cpu_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }

  dynamic "notification" {
    for_each = length(var.capacity.notification_emails) > 0 ? [1] : []

    content {
      email {
        send_to_subscription_administrator    = true
        send_to_subscription_co_administrator = true
        custom_emails                         = var.capacity.notification_emails
      }
    }
  }
}
