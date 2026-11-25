# -----------------------------------------------------------------------------
# Horizontal Autoscale Profile (CPU, Memory & HTTP Request Queue Signals)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = local.effective_autoscale_enabled ? 1 : 0
  name                = "autoscale-${local.name_prefix}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default-autoscale"

    capacity {
      default = var.capacity.min_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    # Scale out on sustained CPU utilization
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
        cooldown  = "PT${var.capacity.scale_out_cooldown_minutes}M"
      }
    }

    # Scale in when CPU utilization subsides
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_in_cooldown_minutes}M"
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
        cooldown  = "PT${var.capacity.scale_out_cooldown_minutes}M"
      }
    }

    # Scale in when memory pressure subsides (Azure Autoscale requires ALL scale-in rules to match)
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.scale_in_cooldown_minutes}M"
      }
    }

    # Rapid burst scale-out on HTTP request queue buildup
    rule {
      metric_trigger {
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.http_queue_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT${var.capacity.scale_out_cooldown_minutes}M"
      }
    }
  }
}
