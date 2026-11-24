# -----------------------------------------------------------------------------
# Horizontal Autoscale Policy (CPU, Memory & HTTP Queue Pressure)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.create_autoscale ? 1 : 0

  name                = local.autoscale_name
  resource_group_name = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "sre-standard-autoscale"

    capacity {
      default = var.capacity.min_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    # Scale out on sustained CPU load
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.capacity.scale_out_cooldown
      }
    }

    # Scale out on memory pressure
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.memory_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.capacity.scale_out_cooldown
      }
    }

    # Rapid scale out on queued HTTP requests (traffic surge protection)
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT2M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.http_queue_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = var.capacity.scale_out_cooldown
      }
    }

    # Conservative scale in on low CPU over a wider 15-minute window to prevent flapping
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.capacity.scale_in_cooldown
      }
    }
  }
}
