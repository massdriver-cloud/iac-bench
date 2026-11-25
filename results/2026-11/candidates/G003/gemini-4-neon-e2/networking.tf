# ------------------------------------------------------------------------------
# Optional Private Endpoint for Internal-Only APIs
# ------------------------------------------------------------------------------

resource "azurerm_private_endpoint" "this" {
  count = var.networking.private_endpoint_subnet_id != null ? 1 : 0

  name                = local.private_ep_name
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = var.networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.web_app_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.networking.private_dns_zone_id != null ? [var.networking.private_dns_zone_id] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }
}
