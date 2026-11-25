# Standard Application Storage Account (Azure Blob Storage)

Reusable OpenTofu module for provisioning standardized, secure-by-default Azure Storage Accounts for application file workloads (user uploads, images/videos, generated reports, and exports) running on **AKS** and **App Service**.

## What This Module Handles Automatically

Application teams provide a handful of obvious inputs and the module enforces organizational standards automatically:

- **Entra ID authentication only** — Shared access keys are disabled (`shared_access_key_enabled = false`), Azure Portal defaults to Entra ID, and your application's Entra ID identity is granted least-privilege `Storage Blob Data Contributor` access (including User Delegation SAS key generation for browser direct uploads/downloads).
- **No public data exposure** — Anonymous blob/container access is blocked at the account level (`allow_nested_items_to_be_public = false`) and every container is created `private`.
- **Encryption & protocol hardening** — HTTPS-only, TLS 1.2 minimum, double encryption at rest (`infrastructure_encryption_enabled = true`), same-tenant copy restriction (`allowed_copy_scope = "AAD"`), cross-tenant replication disabled, and unused protocols (SFTP, NFSv3, local users, HNS) disabled.
- **Deterministic Azure-compliant naming** — Derives a globally unique 10–24 character lowercase alphanumeric name from your subscription, resource group, app name, and environment (no manual wrestling with Azure's 24-character no-hyphen rule).
- **Environment-aware reliability & data protection**:
  - **Non-prod (`dev`, `test`, `staging`)**: `LRS` replication, 7-day blob & container soft delete, blob versioning with 30-day cleanup of previous versions.
  - **Prod (`prod`)**: `GRS` geo-redundant replication, 30-day blob & container soft delete, 14-day point-in-time restore (with change feed), blob versioning with 90-day cleanup of previous versions, and a `CanNotDelete` resource lock.
- **Cost-controlled lifecycle management** — Automatically cleans up old blob versions so versioning never causes unbounded storage growth, and generates per-container tiering/expiration rules (e.g., auto-expiring generated reports and exports).
- **Default-deny network firewall** — Denies public internet traffic by default (`default_action = "Deny"`), with simple inputs for AKS/App Service VNet subnets, outbound IP ranges, or a Private Endpoint (which automatically disables public network access).
- **Consistent governance tagging** — Automatically applies `application`, `environment`, and `managed_by` tags alongside any custom tags.

## Quick Start (Copy & Fill In)

### Minimal Staging Example (`minimal.tfvars`)

```hcl
app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "eastus2"
app_principal_id    = "11111111-1111-1111-1111-111111111111"

containers = {
  uploads = {}
}
```

### Production Example (Private Endpoint, Lifecycle Policies, Diagnostics, Malware Scanning)

```hcl
app_name            = "orders"
environment         = "prod"
resource_group_name = "orders-prod"
location            = "eastus2"
app_principal_id    = "11111111-1111-1111-1111-111111111111"

containers = {
  uploads = {}
  media   = { cool_after_days = 60 }
  reports = { cool_after_days = 30, archive_after_days = 180, expire_after_days = 365 }
  exports = { expire_after_days = 14 }
}

# Optional extra identities
additional_contributor_principal_ids = ["22222222-2222-2222-2222-222222222222"]
reader_principal_ids                 = ["33333333-3333-3333-3333-333333333333"]

# Private networking for AKS / VNet-integrated App Service (disables public access automatically)
private_endpoint = {
  subnet_id            = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<pe-subnet>"
  private_dns_zone_ids = ["/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
}

# Optional CORS for direct browser uploads/downloads via short-lived User Delegation SAS URLs
cors_rules = [
  {
    allowed_origins = ["https://orders.example.com"]
    allowed_methods = ["GET", "PUT", "HEAD"]
  }
]

# Optional observability and upload malware scanning
log_analytics_workspace_id       = "/subscriptions/<sub-id>/resourceGroups/<ops-rg>/providers/Microsoft.OperationalInsights/workspaces/<law>"
enable_defender_malware_scanning = true

tags = {
  team        = "orders"
  cost_center = "cc-1234"
}
```

### Connecting from AKS or App Service

Pass the non-secret `app_env_vars` output (`AZURE_STORAGE_ACCOUNT_NAME`, `AZURE_STORAGE_BLOB_ENDPOINT`) into your AKS Deployment or App Service App Settings, and authenticate using the Azure Identity SDK's `DefaultAzureCredential` (Workload Identity on AKS or Managed Identity on App Service) — no access keys or connection strings required.

For network connectivity, choose one of:
1. **Private Endpoint** (recommended for production): set `private_endpoint`.
2. **VNet Service Endpoints**: pass your AKS node subnet or App Service VNet-integration subnet IDs via `allowed_subnet_ids` (ensure the `Microsoft.Storage` service endpoint is enabled on the subnet).
3. **Outbound IPs**: for App Services without VNet integration, pass their outbound IPv4 addresses via `allowed_ip_ranges`.

## Running OpenTofu

```bash
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```
