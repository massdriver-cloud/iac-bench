# =============================================================================
# Resource group (only when the caller does not supply one)
# =============================================================================

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# =============================================================================
# Capacity: the App Service plan
# =============================================================================

resource "azurerm_service_plan" "this" {
  name                = "plan-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.instance_size

  # Spread instances across availability zones ("zone balancing" in the
  # current App Service API - the successor of zone redundancy).
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags

  # Instance count is intentionally not set here: the autoscale setting below
  # owns worker count and would otherwise fight with Terraform state.

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 3
      error_message = "zone_redundant = true requires min_instances >= 3 so instances can be spread across all three availability zones."
    }

    precondition {
      condition     = !var.zone_redundant || can(regex("^(P[123]v3|P[123]mv3|PC[234])$", var.instance_size))
      error_message = "zone_redundant = true requires a zone-redundant SKU: Pv3, Pmv3 or Premium Container."
    }
  }
}

# =============================================================================
# Capacity: autoscaling
#
# Scale-out on CPU, memory or HTTP queue backpressure; scale-in on CPU only,
# with a longer cooldown so the plan does not flap under bursty traffic.
# =============================================================================

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "as-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "capacity"

    capacity {
      minimum = var.min_instances
      maximum = var.max_instances
      default = var.min_instances
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
        threshold          = var.scale_out_cpu_percent
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
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.scale_in_cpu_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT10M"
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
        threshold          = var.scale_out_memory_percent
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
        metric_name        = "HttpQueueLength"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_http_queue_length
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }
  }

  # Autoscale events go to the same on-call channel as the alerts.
  notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = var.alert_emails
    }
  }
}
