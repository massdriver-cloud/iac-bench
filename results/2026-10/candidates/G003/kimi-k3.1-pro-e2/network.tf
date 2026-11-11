resource "azurerm_private_endpoint" "production" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "${var.name}-pep"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${var.name}-psc"
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
}
