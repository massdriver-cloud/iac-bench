resource "azurerm_private_endpoint" "production" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = local.private_endpoint_name
  resource_group_name = local.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.private_endpoint_name}-connection"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [var.private_dns_zone_ids] : []
    content {
      name                 = "app-service-dns"
      private_dns_zone_ids = private_dns_zone_group.value
    }
  }
}
