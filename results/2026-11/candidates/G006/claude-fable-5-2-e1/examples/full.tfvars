# Every knob the module has, for reference. Most teams need only the first
# four inputs - see README.md.

resource_group_name      = "orders-prod"
application_principal_id = "3f2a6c1e-8b4d-4e7a-9c5f-1d2e3a4b5c6d"

containers = {
  uploads = {}
  media   = { move_to_cool_after_days = 90 }
  exports = { delete_after_days = 30 }
}

allowed_subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/aks-nodes",
]

private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/private-endpoints"
private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"

allowed_ip_ranges    = ["203.0.113.0/24"]
cors_allowed_origins = ["https://orders.example.com"]

reader_group_object_ids = ["9b1f7d52-6c3e-4a8b-b0d4-2e5f6a7c8d90"]

log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/law-prod"

recovery_window_days            = 30
previous_version_retention_days = 90
replication_type                = "GZRS"
delete_lock_enabled             = true

tags = {
  team = "orders"
}
