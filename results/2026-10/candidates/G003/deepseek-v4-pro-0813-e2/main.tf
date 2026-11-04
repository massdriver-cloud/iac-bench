locals {
  # Combined app settings that flow to both slots.
  base_app_settings = merge(
    {
      DOCKER_REGISTRY_SERVER_URL          = var.docker_registry_url
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_ENABLE_CI                    = "true"
    },
    var.app_settings,
    var.app_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    } : {}
  )

  common_tags = merge(var.tags, { "managed-by" = "opentofu" })
}

# ---------------------------------------------------------------------------
# Application Insights (observability)
# ---------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  count               = var.app_insights_enabled ? 1 : 0
  name                = "${var.name}-ai"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# App Service Plan (only when one isn't supplied)
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  count                  = var.app_service_plan_id == null ? 1 : 0
  name                   = "${var.name}-plan"
  location               = var.location
  resource_group_name    = var.resource_group_name
  os_type                = var.os_type
  sku_name               = var.capacity_sku
  worker_count           = var.autoscale == null ? var.worker_count : var.autoscale.min_capacity
  zone_balancing_enabled = var.zone_redundant

  tags = local.common_tags
}

resource "azurerm_monitor_autoscale_setting" "plan" {
  count               = var.autoscale != null && var.app_service_plan_id == null ? 1 : 0
  name                = "${var.name}-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this[0].id

  profile {
    name = "cpu"
    capacity {
      default = var.autoscale.min_capacity
      minimum = var.autoscale.min_capacity
      maximum = var.autoscale.max_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.target_cpu
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.target_cpu / 2
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

locals {
  plan_id = var.app_service_plan_id != null ? var.app_service_plan_id : azurerm_service_plan.this[0].id
}