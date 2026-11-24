resource "random_string" "suffix" {
  count = var.name_suffix == null ? 1 : 0

  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 1 : 0

  name     = coalesce(var.resource_group.name, "rg-${local.base_name}-${local.suffix}")
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# App Service Plan (Capacity & Availability)
# =============================================================================

resource "azurerm_service_plan" "this" {
  count = local.create_service_plan ? 1 : 0

  name                   = local.service_plan_name
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = local.sku_name
  worker_count           = local.min_instances
  zone_balancing_enabled = local.zone_redundant
  tags                   = local.common_tags

  lifecycle {
    # Prevent OpenTofu runs from scaling down an actively autoscaled service during peak load.
    # Minimum/maximum capacity bounds are enforced continuously by the autoscale setting.
    ignore_changes = [worker_count]

    precondition {
      condition     = !local.zone_redundant || local.min_instances >= 3
      error_message = "Zone-redundant availability requires at least 3 instances (capacity.min_instances >= 3)."
    }

    precondition {
      condition     = local.max_instances >= local.min_instances
      error_message = "Resolved capacity.max_instances (${local.max_instances}) must be >= capacity.min_instances (${local.min_instances})."
    }
  }
}

# =============================================================================
# Horizontal Autoscaling (CPU & Memory Saturation)
# =============================================================================

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_active ? 1 : 0

  name                = local.autoscale_name
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this[0].id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = tostring(local.min_instances)
      minimum = tostring(local.min_instances)
      maximum = tostring(local.max_instances)
    }

    # Scale out on sustained CPU saturation
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.cpu_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = tostring(local.scale_step)
        cooldown  = "PT${var.capacity.scale_out_cooldown_minutes}M"
      }
    }

    # Scale out on sustained Memory pressure
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.capacity.memory_scale_out_percent
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = tostring(local.scale_step)
        cooldown  = "PT${var.capacity.scale_out_cooldown_minutes}M"
      }
    }

    # Scale in gradually when CPU utilization is low
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.capacity.cpu_scale_in_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = tostring(local.scale_step)
        cooldown  = "PT${var.capacity.scale_in_cooldown_minutes}M"
      }
    }
  }
}
