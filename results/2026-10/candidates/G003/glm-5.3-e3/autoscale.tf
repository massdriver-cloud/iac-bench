# ---------------------------------------------------------------------------
# Capacity: automatic scaling on the service plan. Scale out quickly on CPU or
# memory pressure, scale back in slowly from a longer window so the service
# does not flap. The plan always starts (and never drops below) min_instances.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}-${var.environment}"
  resource_group_name = local.resource_group_name
  location            = local.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = local.effective_min_instances
      minimum = local.effective_min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_aggregation   = "Average"
        time_window        = "PT10M"
        operator           = "GreaterThan"
        threshold          = 70
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
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_aggregation   = "Average"
        time_window        = "PT10M"
        operator           = "GreaterThan"
        threshold          = 70
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
        time_aggregation   = "Average"
        time_window        = "PT20M"
        operator           = "LessThan"
        threshold          = 25
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
        time_aggregation   = "Average"
        time_window        = "PT20M"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }

  # Scale events go to the same inboxes as the alerts.
  dynamic "notification" {
    for_each = length(var.alert_emails) > 0 ? [true] : []

    content {
      email {
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
        custom_emails                         = var.alert_emails
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.max_instances >= local.effective_min_instances
      error_message = "max_instances (${var.max_instances}) must be >= the effective minimum (${local.effective_min_instances}). Note that zone-redundant tiers require at least 3 minimum instances."
    }

    precondition {
      condition     = var.max_instances <= local.tier.instance_limit
      error_message = "The '${var.tier}' tier (${local.tier.sku}) supports at most ${local.tier.instance_limit} instances, but max_instances is ${var.max_instances}."
    }
  }
}
