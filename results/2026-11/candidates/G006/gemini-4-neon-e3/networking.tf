# Optional Private Endpoint for the blob service.
# When private_endpoint_subnet_id is provided, public_network_access_enabled is
# automatically set to false on the storage account so all blob traffic traverses
# the private VNet backbone.

resource "azurerm_private_endpoint" "blob" {
  count = local.use_private_endpoint ? 1 : 0

  name                = "pe-${local.storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [1] : []
    content {
      name                 = "blob-dns-zone-group"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = local.standard_tags
}
