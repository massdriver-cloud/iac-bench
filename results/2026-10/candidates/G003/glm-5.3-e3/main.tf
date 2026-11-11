data "azurerm_client_config" "current" {}

# Used only when deploying into a pre-existing resource group; its location wins.
data "azurerm_resource_group" "existing" {
  count = var.resource_group_name == null ? 0 : 1
  name  = var.resource_group_name
}

# The module owns a resource group per service unless told otherwise.
resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "rg-${var.name}-${var.environment}"
  location = var.location
  tags     = local.tags
}
