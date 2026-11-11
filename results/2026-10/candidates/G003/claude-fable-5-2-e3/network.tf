###############################################################################
# Private inbound access (optional)
###############################################################################

resource "azurerm_private_endpoint" "app" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "pep-${local.app_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.app_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }

  tags = local.tags
}

# A slot is a separate private-link sub-resource of the same site; without its
# own endpoint the release candidate could not be verified privately.
resource "azurerm_private_endpoint" "staging" {
  count = var.private_endpoint_subnet_id != null && var.staging_slot_enabled ? 1 : 0

  name                = "pep-${local.app_name}-${local.slot_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.app_name}-${local.slot_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites-${local.slot_name}"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }

  tags = local.tags

  depends_on = [azurerm_linux_web_app_slot.staging]
}
