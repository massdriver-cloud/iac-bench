application_name         = "orders"
environment              = "prod"
resource_group_name      = "orders-prod"
application_principal_id = "11111111-1111-1111-1111-111111111111"
location                 = "eastus2"

containers = {
  uploads = {}
  media   = {}
  reports = {
    lifecycle_tier_to_cool_after_days = 90
    lifecycle_tier_to_cold_after_days = 180
  }
  temp-exports = {
    lifecycle_delete_after_days = 14
  }
}

additional_role_assignments = {
  analytics = {
    principal_id         = "22222222-2222-2222-2222-222222222222"
    role_definition_name = "Storage Blob Data Reader"
  }
}

cors_allowed_origins       = ["https://orders.example.com"]
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-pe"
private_dns_zone_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/obs-prod/providers/Microsoft.OperationalInsights/workspaces/law-prod"
