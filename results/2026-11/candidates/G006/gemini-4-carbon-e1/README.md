# Application Blob Storage Module

Standard OpenTofu module for application teams running on **AKS** and **App Service** to provision Azure Blob Storage for user uploads, images and videos, and generated reports and exports.

## Quick Start (Minimal Example)

Provide your application name, environment, existing resource group, region, and your application's Entra ID Object ID:

```hcl
app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "eastus2"
app_principal_id    = "11111111-2222-3333-4444-555555555555"
```

Out of the box, this creates a compliant `StorageV2` account in your resource group, disables shared access keys and public anonymous access, grants your application identity `Storage Blob Data Contributor`, creates a default `files` container, enables versioning and soft delete, and automatically tiers unaccessed files to Cool/Cold storage while promoting re-accessed files back to Hot.

---

## Common Customizations

### Multiple Containers & Expiring Reports/Exports

```hcl
app_name            = "orders"
environment         = "prod"
resource_group_name = "orders-prod"
location            = "eastus2"
app_principal_id    = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media   = {}
  exports = {
    delete_after_days    = 30
    reader_principal_ids = ["44444444-2222-3333-4444-555555555555"] # downstream reporting service
  }
}
```

### Browser Direct Uploads / Media Delivery (CORS + User Delegation SAS)

Shared keys are disabled; mint short-lived **User Delegation SAS** URLs using your application's Entra ID identity (`Storage Blob Data Contributor` includes `generateUserDelegationKey`) and configure `cors_rules`:

```hcl
cors_rules = [
  {
    allowed_origins = ["https://orders.example.com"]
  }
]
```

### Network Isolation (AKS / App Service VNet or Private Link)

- **Service Endpoints:** Pass `allowed_subnet_ids` (and/or `allowed_ip_ranges`) to automatically switch the storage firewall default action to `Deny`.
- **Private Endpoint:** Pass `private_endpoint_subnet_id` (and optional `private_dns_zone_ids`) to provision a Blob Private Endpoint in your resource group and disable public network access automatically.

---

## Environment-Aware Defaults

| Setting | Non-Production (`dev`, `staging`, etc.) | Production (`prod`, `production`, `prd`) | Override Variable |
|---|---|---|---|
| Replication | `LRS` | `GZRS` (zone + geo-redundant) | `replication_type` |
| Blob / Container Soft Delete | `7` days | `30` days | `soft_delete_retention_days` |
| Point-in-Time Restore | Disabled (`0`) | `14` days | `point_in_time_restore_days` |
| Overwritten Version Cleanup | `30` days | `90` days | `noncurrent_version_retention_days` |
| `CanNotDelete` Resource Lock | `false` | `true` | `enable_delete_lock` |
| Automatic Cool / Cold Tiering | `30` / `90` days since last access | `30` / `90` days since last access | `default_cool_after_days` / `default_cold_after_days` |

---

## Connecting from AKS & App Service

Wire the `app_settings` output (or `primary_blob_endpoint`) into your App Service settings or AKS `ConfigMap`, and authenticate with `DefaultAzureCredential`—no storage keys or connection strings required:

- `AZURE_STORAGE_ACCOUNT_NAME`
- `AZURE_STORAGE_BLOB_ENDPOINT` (e.g. `https://stordersstga1b2c3.blob.core.windows.net/`)
- `AZURE_STORAGE_CONTAINERS`
