# -----------------------------------------------------------------------------
# Horizontal Autoscaling (CPU, Memory & HTTP Queue Depth)
# -----------------------------------------------------------------------------
# Note on Azure Monitor Autoscale evaluation semantics:
# - Scale-out (Increase) rules evaluate with OR semantics: breaching CPU, Memory,
#   OR HTTP Queue depth immediately triggers scale-out.
# - Scale-in (Decrease) rules evaluate with AND semantics: workers only scale in
#   when BOTH CPU AND Memory remain below their respective scale-in thresholds.

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = local.autoscale_enabled ? 1 : 0
  name                = substr("autoscale-${local.base_name}", 0, 60)
  resource_group_name = local.effective_resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = var.capacity.min_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    # Scale out on sustained CPU utilization
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.capacity.autoscale.scale_out_window_minutes}M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.autoscale.cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.autoscale.scale_out_cooldown_minutes}M"
      }
    }

    # Scale out on sustained Memory utilization
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.capacity.autoscale.scale_out_window_minutes}M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.autoscale.memory_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.autoscale.scale_out_cooldown_minutes}M"
      }
    }

    # Scale out on HTTP request queue backpressure
    dynamic "rule" {
      for_each = var.capacity.autoscale.http_queue_scale_out_count != null ? [var.capacity.autoscale.http_queue_scale_out_count] : []
      content {
        metric_trigger {
          metric_name        = "HttpQueueLength"
          metric_namespace   = "microsoft.web/serverfarms"
          metric_resource_id = azurerm_service_plan.this[0].id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = "PT${var.capacity.autoscale.scale_out_window_minutes}M"
          time_aggregation   = "Average"
          operator           = "GreaterThan"
          threshold          = rule.value
        }

        scale_action {
          direction = "Increase"
          type      = "ChangeCount"
          value     = "1"
          cooldown  = "PT${var.capacity.autoscale.scale_out_cooldown_minutes}M"
        }
      }
    }

    # Scale in only when BOTH CPU and Memory have cooled down
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.capacity.autoscale.scale_in_window_minutes}M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.autoscale.cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.autoscale.scale_in_cooldown_minutes}M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_namespace   = "microsoft.web/serverfarms"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.capacity.autoscale.scale_in_window_minutes}M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.autoscale.memory_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.capacity.autoscale.scale_in_cooldown_minutes}M"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.sku_supports_autoscale
      error_message = "Horizontal autoscaling (capacity.max_instances > capacity.min_instances) requires a Standard, Premium, or Isolated SKU (current SKU: ${var.capacity.sku_name})."
    }
  }
}
