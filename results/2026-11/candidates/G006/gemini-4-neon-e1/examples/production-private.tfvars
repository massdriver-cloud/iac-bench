# Production example with Private Endpoint connectivity, per-container lifecycle rules,
# direct browser upload support (User Delegation SAS + CORS), container-scoped RBAC,
# Azure Monitor diagnostics, and Microsoft Defender malware scanning.
#
# In "prod", the module automatically enables:
#   - Geo-redundant storage (GRS)
#   - 30-day blob and container soft delete
#   - Blob versioning + change feed + 7-day point-in-time restore
#   - 90-day automatic cleanup of noncurrent versions
#   - CanNotDelete management lock

application_name         = "orders"
environment              = "prod"
resource_group_name      = "orders-prod"
location                 = "eastus2"
application_principal_id = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media = {
    tier_to_cool_after_days    = 90
    tier_to_archive_after_days = 365
  }
  reports = {
    tier_to_cool_after_days = 30
    delete_after_days       = 180
  }
}

# Clean up temporary upload chunks after 3 days.
additional_lifecycle_rules = [
  {
    name              = "expire-temp-uploads"
    prefix_match      = ["uploads/tmp/"]
    delete_after_days = 3
  }
]

# Private networking for AKS / App Service VNet integration (automatically disables public network access).
private_endpoint = {
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-private-endpoints"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}

# Allow the app to mint short-lived User Delegation SAS tokens for direct browser uploads.
enable_user_delegation_sas = true

cors_rules = [
  {
    allowed_origins = ["https://orders.example.com"]
    allowed_methods = ["GET", "HEAD", "PUT", "OPTIONS"]
    allowed_headers = ["x-ms-blob-type", "content-type"]
    exposed_headers = ["ETag"]
  }
]

# Grant a separate analytics service read-only access to the reports container only.
additional_role_assignments = {
  analytics_reports_reader = {
    principal_id   = "22222222-3333-4444-5555-666666666666"
    role_name      = "Storage Blob Data Reader"
    container_name = "reports"
    description    = "Read-only access for analytics pipeline on generated reports."
  }
}

# Observability and untrusted upload protection.
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/law-platform-prod"
enable_malware_scanning    = true

owner       = "orders-team"
cost_center = "cc-4200"
tags = {
  data_classification = "confidential"
}
