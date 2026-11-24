# Replace the example values with your app and network details.
resource_group_name      = "orders-staging"
application_principal_id = "11111111-2222-4333-8444-555555555555"

private_endpoint = {
  subnet_id           = "/subscriptions/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee/resourceGroups/network-staging/providers/Microsoft.Network/virtualNetworks/staging/subnets/private-endpoints"
  private_dns_zone_id = "/subscriptions/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee/resourceGroups/network-staging/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}
