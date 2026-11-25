# A fuller production example. Copy, then replace the IDs with your own.
#
#   tofu plan -var-file=examples/prod.tfvars

application = "orders"
environment = "prod"
location    = "westeurope"

# Object ID of the application's identity in Entra ID.
application_principal_id = "3f2b8c1e-7a4d-4e6b-9c0f-5d1a2b3c4e5f"

# Where the application reaches the storage from.
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/private-endpoints"
private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"

containers = {
  uploads = {}
  media   = {}
  exports = { delete_after_days = 30 }
}

# Audit log of every read / write / delete.
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/log-prod"

tags = {
  team = "orders"
}
