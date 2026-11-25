# Private access is opt-in: hand the module a subnet and it does the whole
# job - private endpoints for the blob and file services, the privatelink DNS
# zones, and the virtual network links so account hostnames resolve to the
# private IPs. Public network access is disabled on the account when this is
# configured (see locals.tf).
resource "azurerm_private_dns_zone" "this" {
  for_each = toset(local.private_endpoints_enabled ? ["blob", "file"] : [])

  name                = "privatelink.${each.value}.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name                  = "link-${local.storage_account_name}-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = local.virtual_network_id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "this" {
  for_each = toset(local.private_endpoints_enabled ? ["blob", "file"] : [])

  name                = "pe-${local.storage_account_name}-${each.value}"
  location            = local.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "pe-${local.storage_account_name}-${each.value}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.value]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.value].id]
  }
}
