# ---------------------------------------------------------------------------------------------
# Plan: one dedicated Linux Premium v3 plan per service, so a service's capacity, scaling and
# blast radius are its own.
# ---------------------------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.min_instances
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = local.tags

  lifecycle {
    # The instance count is owned by the autoscale setting below (also for fixed capacity). Without
    # this, every apply would yank the plan back to min_instances in the middle of a traffic peak.
    ignore_changes = [worker_count]
  }
}

# ---------------------------------------------------------------------------------------------
# Autoscale. Always present: with min_instances == max_instances it simply pins the instance count,
# which keeps a single owner for capacity in every configuration.
#
# Scale out fast on either signal (5 min window, +1, 5 min cooldown); scale in slowly and only when
# both signals are low (10 min window, -1, 10 min cooldown).
# ---------------------------------------------------------------------------------------------

locals {
  autoscale_enabled = var.capacity.max_instances > var.capacity.min_instances

  autoscale_rules = local.autoscale_enabled ? [
    { metric = "CpuPercentage", operator = "GreaterThan", threshold = var.capacity.cpu_scale_out_percent, direction = "Increase", window = "PT5M", cooldown = "PT5M" },
    { metric = "MemoryPercentage", operator = "GreaterThan", threshold = var.capacity.memory_scale_out_percent, direction = "Increase", window = "PT5M", cooldown = "PT5M" },
    { metric = "CpuPercentage", operator = "LessThan", threshold = var.capacity.cpu_scale_out_percent - 30, direction = "Decrease", window = "PT10M", cooldown = "PT10M" },
    { metric = "MemoryPercentage", operator = "LessThan", threshold = var.capacity.memory_scale_out_percent - 20, direction = "Decrease", window = "PT10M", cooldown = "PT10M" },
  ] : []
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.capacity.min_instances
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
    }

    dynamic "rule" {
      for_each = local.autoscale_rules

      content {
        metric_trigger {
          metric_name        = rule.value.metric
          metric_resource_id = azurerm_service_plan.this.id
          metric_namespace   = "Microsoft.Web/serverfarms"
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = rule.value.window
          time_aggregation   = "Average"
          operator           = rule.value.operator
          threshold          = rule.value.threshold
        }

        scale_action {
          direction = rule.value.direction
          type      = "ChangeCount"
          value     = "1"
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}
