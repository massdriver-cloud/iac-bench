# -----------------------------------------------------------------------------
# Locals: the naming and sizing decisions the module owns.
# -----------------------------------------------------------------------------

locals {
  name = lower(var.name)

  # The standard compute ladder. Premium v3 is the floor of the standard: it
  # is the family that runs Linux containers, autoscales and is zone-redundant
  # in zone-capable regions.
  size_to_sku = {
    small  = "P1v3"
    medium = "P2v3"
    large  = "P3v3"
  }

  sku_name = var.instance_sku != null ? var.instance_sku : local.size_to_sku[var.instance_size]

  # Registry the image is pulled from: an explicit URL wins, otherwise it is
  # derived from the ACR resource ID, otherwise the public Microsoft registry.
  container_registry_url = coalesce(
    var.container_registry_url,
    var.container_registry_id != null ? "https://${regex("[^/]+$", var.container_registry_id)}.azurecr.io" : null,
    "https://mcr.microsoft.com",
  )

  app_name = "app-${local.name}"

  tags = merge({ service = local.name }, var.tags)

  # Runtime environment handed to the container. SRE-provided app_settings are
  # merged on top, so a service can override any module default.
  app_settings = merge(
    {
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
      "WEBSITES_PORT"                         = tostring(var.container_port)
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    },
    var.app_settings,
  )

  # Every identity that must be able to pull the container image.
  pull_principals = merge(
    { production = azurerm_linux_web_app.this.identity[0].principal_id },
    { for slot_name, slot in azurerm_linux_web_app_slot.this : slot_name => slot.identity[0].principal_id },
  )
}

# -----------------------------------------------------------------------------
# Capacity: one resource group and one App Service plan per service.
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                = "plan-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = local.sku_name
  worker_count        = var.min_instances
  tags                = local.tags

  lifecycle {
    # After creation the autoscale setting owns the running instance count;
    # Terraform only seeds the floor value.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.min_instances <= var.max_instances
      error_message = "min_instances (${var.min_instances}) must not exceed max_instances (${var.max_instances})."
    }
  }
}

# Capacity management: CPU-driven autoscale between min_instances and
# max_instances. Scale-out reacts to 10 minutes of sustained load; scale-in is
# deliberately slower so that short spikes do not thrash the plan.
resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "cpu"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        time_aggregation   = "Average"
        statistic          = "Average"
        time_window        = "PT10M"
        operator           = "GreaterThan"
        threshold          = var.cpu_scale_out_threshold
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
        time_aggregation   = "Average"
        statistic          = "Average"
        time_window        = "PT15M"
        operator           = "LessThan"
        threshold          = var.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.cpu_scale_out_threshold > var.cpu_scale_in_threshold
      error_message = "cpu_scale_out_threshold must be greater than cpu_scale_in_threshold, otherwise the two rules fight each other."
    }
  }
}
