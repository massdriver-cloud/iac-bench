resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = local.service_plan_id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "cpu-baseline"

    capacity {
      minimum = tostring(var.autoscale_min_capacity)
      default = tostring(var.autoscale_default_capacity)
      maximum = tostring(var.autoscale_max_capacity)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_scale_out_cpu_threshold
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
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_scale_in_cpu_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  dynamic "notification" {
    for_each = length(var.autoscale_notification_emails) > 0 ? [1] : []
    content {
      email {
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
        custom_emails                         = var.autoscale_notification_emails
      }
    }
  }
}
