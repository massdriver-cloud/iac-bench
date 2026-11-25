# ---------------------------------------------------------------------------
# Private endpoints: how apps on AKS/App Service reach the account without
# ever crossing the public internet. One endpoint per storage service the
# account exposes (blob always; file/queue when requested).
#
# Wiring is opt-in via `private_endpoint_subnet_id` because not every app has
# its VNet ready yet; until then the deny-by-default network rules mean the
# account is simply unreachable, which is the safe state.
# ---------------------------------------------------------------------------

locals {
  private_endpoint_subresources = var.private_endpoint_subnet_id == null ? toset([]) : toset(concat(
    ["blob"],
    length(var.queues) > 0 ? ["queue"] : [],
    length(var.file_shares) > 0 ? ["file"] : [],
  ))
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoint_subresources

  name                = "${azurerm_storage_account.this.name}-${each.value}"
  resource_group_name = local.resource_group_name
  location            = local.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "${azurerm_storage_account.this.name}-${each.value}"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = [each.value]
  }

  dynamic "private_dns_zone_group" {
    for_each = lookup(var.private_dns_zone_ids, each.value, null) != null ? [lookup(var.private_dns_zone_ids, each.value)] : []

    content {
      name                 = "${each.value}-dns"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }
}
