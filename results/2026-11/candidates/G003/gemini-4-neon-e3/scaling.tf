# ------------------------------------------------------------------------------
# Azure Monitor Autoscale (CPU, Memory & HTTP Queue Length)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_enabled ? 1 : 0

  name                = local.autoscale_name
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = tostring(var.capacity.min_instances)
      minimum = tostring(var.capacity.min_instances)
      maximum = tostring(var.capacity.max_instances)
    }

    # Scale OUT on sustained high CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.autoscale.cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = local.scale_step
        cooldown  = local.cooldown_iso8601
      }
    }

    # Scale OUT on sustained high memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.autoscale.memory_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = local.scale_step
        cooldown  = local.cooldown_iso8601
      }
    }

    # Scale OUT on HTTP request queuing
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.autoscale.http_queue_scale_out
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = local.scale_step
        cooldown  = local.cooldown_iso8601
      }
    }

    # Scale IN conservatively only when BOTH CPU and Memory remain low for 10m
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.autoscale.cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = local.scale_step
        cooldown  = local.cooldown_iso8601
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.autoscale.memory_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = local.scale_step
        cooldown  = local.cooldown_iso8601
      }
    }
  }
}
