resource "azurerm_service_plan" "autoscaled" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name
  worker_count        = var.autoscale_default_capacity

  per_site_scaling_enabled        = false
  premium_plan_auto_scale_enabled = false
  zone_balancing_enabled          = var.zone_redundant
  tags                            = local.common_tags

  lifecycle {
    # The autoscaler, rather than a later tofu apply, owns current capacity.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.autoscale_min_capacity <= var.autoscale_default_capacity && var.autoscale_default_capacity <= var.autoscale_max_capacity
      error_message = "Autoscale capacity must satisfy min <= default <= max."
    }

    precondition {
      condition     = !var.zone_redundant || var.autoscale_min_capacity >= 3
      error_message = "A zone-redundant autoscaled plan requires autoscale_min_capacity of at least 3."
    }

    precondition {
      condition     = var.autoscale_scale_in_cpu_threshold < var.autoscale_scale_out_cpu_threshold
      error_message = "autoscale_scale_in_cpu_threshold must be lower than autoscale_scale_out_cpu_threshold."
    }
  }
}

resource "azurerm_service_plan" "manual" {
  count = var.autoscale_enabled ? 0 : 1

  name                = "${var.name}-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name
  worker_count        = var.instance_count

  per_site_scaling_enabled        = false
  premium_plan_auto_scale_enabled = false
  zone_balancing_enabled          = var.zone_redundant
  tags                            = local.common_tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.instance_count >= 3
      error_message = "A zone-redundant manually scaled plan requires instance_count of at least 3."
    }
  }
}
