# Example: use your application's resource group, identity, and platform network references.
resource_group_name        = "orders-staging"
application_principal_id   = "11111111-1111-4111-8111-111111111111"
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-staging/providers/Microsoft.Network/virtualNetworks/apps-staging/subnets/private-endpoints"
blob_private_dns_zone_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-staging/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
