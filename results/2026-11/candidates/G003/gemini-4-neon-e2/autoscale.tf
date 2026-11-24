# ------------------------------------------------------------------------------
# Azure Monitor Autoscale Policy (CPU, Memory & HTTP Queue Length)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.create_service_plan && var.capacity.autoscale_enabled ? 1 : 0

  name                = local.autoscale_name
  resource_group_name = local.rg_name
  location            = local.rg_location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = tostring(local.effective_default_instances)
      minimum = tostring(local.effective_min_instances)
      maximum = tostring(local.effective_max_instances)
    }

    # Scale out on sustained high CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThanOrEqual"
        threshold          = var.capacity.cpu_scale_out_pct
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = var.availability.zone_redundant ? "3" : "1"
        cooldown  = var.capacity.scale_out_cooldown
      }
    }

    # Scale in cautiously on sustained low CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThanOrEqual"
        threshold          = var.capacity.cpu_scale_in_pct
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = var.availability.zone_redundant ? "3" : "1"
        cooldown  = var.capacity.scale_in_cooldown
      }
    }

    # Scale out on sustained high Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThanOrEqual"
        threshold          = var.capacity.mem_scale_out_pct
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = var.availability.zone_redundant ? "3" : "1"
        cooldown  = var.capacity.scale_out_cooldown
      }
    }

    # Scale in cautiously on sustained low Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThanOrEqual"
        threshold          = var.capacity.mem_scale_in_pct
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = var.availability.zone_redundant ? "3" : "1"
        cooldown  = var.capacity.scale_in_cooldown
      }
    }

    # Scale out when HTTP request queue builds up (protects tail latency on APIs)
    dynamic "rule" {
      for_each = var.capacity.http_queue_scale_out != null ? [var.capacity.http_queue_scale_out] : []
      content {
        metric_trigger {
          metric_name        = "HttpQueueLength"
          metric_resource_id = azurerm_service_plan.this[0].id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = "PT5M"
          time_aggregation   = "Average"
          operator           = "GreaterThanOrEqual"
          threshold          = rule.value
        }

        scale_action {
          direction = "Increase"
          type      = "ChangeCount"
          value     = var.availability.zone_redundant ? "3" : "1"
          cooldown  = var.capacity.scale_out_cooldown
        }
      }
    }
  }
}
