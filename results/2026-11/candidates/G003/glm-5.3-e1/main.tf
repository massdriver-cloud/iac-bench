# -----------------------------------------------------------------------------
# Resource group and the shared service plan that provides capacity.
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = local.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name
  worker_count        = var.min_instances
  tags                = local.tags

  lifecycle {
    # The autoscale profile below owns the live instance count of the plan:
    # `min_instances` is the floor it enforces (and the count the plan is
    # created with), not a value that is reconciled on every apply.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances (${var.max_instances}) must be greater than or equal to min_instances (${var.min_instances})."
    }
  }
}
