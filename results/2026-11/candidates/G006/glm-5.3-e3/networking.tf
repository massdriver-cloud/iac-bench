# Private access is opt-in, for teams whose applications run inside a virtual
# network (VNet-injected App Service, private AKS). When subnet IDs are given
# the module
#   - creates a blob private endpoint in each subnet,
#   - turns the public endpoint off (unless explicitly overridden), and
#   - makes "<account>.blob.core.windows.net" resolve to the private IP:
#     either in an existing private DNS zone (`private_dns_zone_id`), or in a
#     zone the module creates and links to every virtual network involved.

resource "azurerm_private_dns_zone" "blob" {
  count = local.create_private_dns_zone ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  for_each = {
    for virtual_network_id in local.virtual_network_ids :
    virtual_network_id => virtual_network_id
    if local.create_private_dns_zone
  }

  name                  = "link-${local.storage_account_name}-${substr(element(reverse(split("/", each.key)), 0), 0, 40)}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = "privatelink.blob.core.windows.net"
  virtual_network_id    = each.value

  tags = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  for_each = local.private_endpoint_subnets

  name                = "pe-${local.storage_account_name}-${each.key}"
  location            = local.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value

  private_service_connection {
    name                           = "pe-${local.storage_account_name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_private_dns_zone_id]
  }

  tags = local.tags
}
