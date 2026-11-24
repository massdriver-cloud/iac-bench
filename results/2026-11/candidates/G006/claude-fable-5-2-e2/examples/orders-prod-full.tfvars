# Example: every optional input in use. Most teams only need orders-prod.tfvars.

application              = "orders"
environment              = "prod"
application_principal_id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

# Only needed when the resource group is not named <application>-<environment>.
# resource_group_name = "rg-orders-production"

containers = {
  uploads = {}
  media   = {}
  reports = { delete_after_days = 90 }
  exports = { delete_after_days = 30 }
}

cors_allowed_origins = ["https://orders.example.com"]

read_only_principal_ids = {
  support-team = "1b4e28ba-2fa1-11d2-883f-0016d3cca427"
}

allowed_subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/aks-nodes",
]
allowed_ip_ranges = ["203.0.113.0/24", "198.51.100.7"]

private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/private-endpoints"
private_dns_zone_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net",
]

log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/monitoring/providers/Microsoft.OperationalInsights/workspaces/law-prod"

tags = {
  cost-center = "1234"
}
