# Standard Application Storage Account Module

Reusable OpenTofu module for provisioning standardized, secure-by-default Azure Blob Storage accounts for application teams running on **AKS** and **App Service**.

## Quick Start

Copy this minimal example into your `.tfvars` file and fill in your application details:

```hcl
application_name    = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "eastus2"
app_principal_id    = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  reports = {
    retention_days = 90
  }
}
```

### Connecting from AKS or App Service

Pass the `primary_blob_endpoint` output to your Azure Storage SDK with `DefaultAzureCredential`. No account keys or connection strings are needed (shared key access is disabled by design):

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient(
    account_url=os.environ["STORAGE_BLOB_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
```

For browser uploads/downloads (images, videos, generated reports), your application identity has permission via `Storage Blob Data Contributor` to issue short-lived **User Delegation SAS** URLs signed by Microsoft Entra ID.

## Production Example (Private Endpoint + Diagnostics)

```hcl
application_name    = "orders"
environment         = "prod"
resource_group_name = "orders-prod"
location            = "eastus2"
app_principal_id    = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media   = {}
  reports = {
    retention_days = 90
  }
}

# Private VNet access (automatically disables public network access)
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/orders-prod/providers/Microsoft.Network/virtualNetworks/app-vnet/subnets/private-endpoints"
private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"

# Optional cross-region disaster recovery (upgrades prod ZRS -> GZRS)
enable_geo_redundancy = true

# Optional audit logging and metrics
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/observability-prod/providers/Microsoft.OperationalInsights/workspaces/platform-logs"

# Optional direct browser upload origins
cors_allowed_origins = ["https://orders.example.com"]

tags = {
  team        = "checkout"
  cost_center = "cc-1042"
}
```

## What the Module Handles Automatically

| Area | Standard Behavior |
|---|---|
| **Naming** | Generates a globally unique, compliant name (`st<app><env><6-char-suffix>`, 3–24 lowercase alphanumeric chars). |
| **Authentication** | Disables Shared Access Keys (`shared_access_key_enabled = false`), defaults to OAuth, and grants `app_principal_id` least-privilege `Storage Blob Data Contributor`. |
| **Transport & Encryption** | Enforces HTTPS-only, TLS 1.2+, double infrastructure encryption at rest, disables SFTP/local users and cross-tenant replication. |
| **Container Privacy** | Disallows anonymous public blob access at the account level; all containers are `private`. |
| **Networking** | Firewall defaults to `Deny` (allowing `AzureServices`, `Logging`, `Metrics`). Supports AKS/App Service VNet service endpoints (`allowed_subnet_ids`), approved egress IPs (`allowed_ip_ranges`), or full Private Endpoint (`private_endpoint_subnet_id`, which disables public access). |
| **Redundancy** | `prod` uses `ZRS` (`GZRS` with `enable_geo_redundancy = true`); non-prod uses `LRS` (`GRS` with `enable_geo_redundancy = true`). |
| **Data Protection** | Blob versioning everywhere; soft delete for blobs & containers (30d in `prod`, 7d in non-prod); 14-day Point-in-Time Restore & Change Feed in `prod`; `CanNotDelete` resource lock in `prod`. |
| **Cost Control** | Moves untouched blobs to Cool (30d) and Cold (90d) with automatic Cool-to-Hot rehydration on access, cleans up old noncurrent versions (90d `prod`, 14d non-prod), and expires blobs in containers with `retention_days`. |
| **Tagging** | Enforces `application`, `environment`, and `managed_by = "opentofu"` tags merged with caller-supplied `tags`. |
