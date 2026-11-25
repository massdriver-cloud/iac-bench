# =============================================================================
# Optional Private Endpoint (Recommended for AKS & App Service VNet Integration)
# =============================================================================

resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint != null ? 1 : 0

  name                = "pe-${azurerm_storage_account.this.name}-blob"
  location            = azurerm_storage_account.this.location
  resource_group_name = azurerm_storage_account.this.resource_group_name
  subnet_id           = var.private_endpoint.subnet_id

  private_service_connection {
    name                           = "psc-${azurerm_storage_account.this.name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_endpoint.private_dns_zone_id != null ? [var.private_endpoint.private_dns_zone_id] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = local.tags
}
