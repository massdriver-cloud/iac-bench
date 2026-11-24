# =====================================================================================================================
# Resource Group
# =====================================================================================================================

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# =====================================================================================================================
# Capacity & App Service Plan
# =====================================================================================================================

resource "azurerm_service_plan" "this" {
  count                  = var.service_plan_id == null ? 1 : 0
  name                   = local.plan_name
  resource_group_name    = local.resource_group_name
  location               = local.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  zone_balancing_enabled = var.zone_redundancy_enabled
  worker_count           = local.effective_default_capacity
  tags                   = local.tags
}

# =====================================================================================================================
# Horizontal Autoscaling
# =====================================================================================================================

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.service_plan_id == null && var.autoscale_enabled ? 1 : 0
  name                = "autoscale-${local.plan_name}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this[0].id
  tags                = local.tags

  profile {
    name = "default-autoscaling-profile"

    capacity {
      default = local.effective_default_capacity
      minimum = local.effective_min_capacity
      maximum = local.effective_max_capacity
    }

    # Scale out on high CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in on low CPU
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale out on high Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_memory_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in on low Memory
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}
