# =============================================================================
# Private networking (optional)
# =============================================================================

# Private endpoints are an opt-in path for applications that must reach their
# blobs over private networking. The module never creates the
# "privatelink.blob.core.windows.net" DNS zone itself: that zone is shared
# platform infrastructure, so the platform team owns it and app teams pass its
# ID in via private_dns_zone_id.
resource "azurerm_private_endpoint" "blob" {
  count = var.private_endpoint_subnet_id != null ? 1 : 0

  name                = "pe-${local.storage_account_name}-blob"
  location            = local.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "pe-${local.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = local.common_tags
}
