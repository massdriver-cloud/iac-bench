locals {
  service_plan_id = var.autoscale.enabled ? azurerm_service_plan.autoscaled[0].id : azurerm_service_plan.fixed[0].id
}

# Separate addresses allow static lifecycle policies: Azure owns elastic worker
# count, while OpenTofu owns fixed worker count. See README before changing modes.
resource "azurerm_service_plan" "fixed" {
  count                  = var.autoscale.enabled ? 0 : 1
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.instance_count
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.instance_count >= 3
      error_message = "Zone redundancy requires at least three workers."
    }
  }
}

resource "azurerm_service_plan" "autoscaled" {
  count                  = var.autoscale.enabled ? 1 : 0
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.instance_count
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    ignore_changes = [worker_count]
    precondition {
      condition     = !var.zone_redundant || var.instance_count >= 3
      error_message = "Zone redundancy requires at least three workers."
    }
    precondition {
      condition     = var.autoscale.max_instances >= var.instance_count
      error_message = "Autoscale maximum cannot be below the minimum instance count."
    }
  }
}
