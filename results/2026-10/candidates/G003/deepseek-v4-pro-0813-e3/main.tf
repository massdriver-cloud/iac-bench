# ---------------------------------------------------------------------------
# Core resources: resource group and App Service Plan.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}-${local.suffix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "plan-${local.name}"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku.size
  worker_count           = var.sku.capacity
  zone_balancing_enabled = local.effective_zone_redundant
  tags                   = var.tags
}