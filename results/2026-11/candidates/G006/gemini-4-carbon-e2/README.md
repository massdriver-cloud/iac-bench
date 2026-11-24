# Application Blob Storage Account Module

Standard OpenTofu module for provisioning an Azure Storage Account for application files (user uploads, images and videos, generated reports and exports) running on **AKS** and **App Service**.

## Opinionated Defaults

Application teams only need to provide five obvious inputs (`app_name`, `environment`, `resource_group_name`, `location`, `principal_id`). Everything else is configured securely out of the box:

- **Collision-free Azure naming**: Automatically builds a valid 3–24 character lowercase alphanumeric storage account name (`st<app><env><suffix>`).
- **Zero shared keys / Entra ID native**: Shared Access Keys and local SFTP users are disabled (`shared_access_key_enabled = false`). Access is granted via Entra ID RBAC (`Storage Blob Data Contributor` + `Storage Blob Delegator` for issuing short-lived User Delegation SAS URLs).
- **Private by default**: Anonymous public blob/container access is blocked at the account level, HTTPS and TLS 1.2+ are enforced, double encryption at rest (`infrastructure_encryption_enabled = true`) is enabled, and cross-tenant replication is disabled.
- **Environment-aware resilience & cost management**:
  - **Production** (`prod`, `production`, `prd`): Zone-Redundant Storage (`ZRS`, or `GRS` in regions without Availability Zones), 30-day blob/container soft delete, blob versioning, and 90-day automatic cleanup of non-current versions/snapshots.
  - **Non-production** (`dev`, `staging`, etc.): Locally-Redundant Storage (`LRS`), 7-day soft delete, blob versioning, and 14-day cleanup of non-current versions/snapshots.

---

## Quick Start (Minimal Example)

```hcl
app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "eastus2"
principal_id        = "11111111-2222-3333-4444-555555555555" # App's Entra ID Object ID
```

This creates a hardened storage account in `orders-staging`, a private `files` container, lifecycle cleanup for overwritten versions, and grants your application identity full read/write blob access plus User Delegation SAS signing.

---

## Production Example (Custom Containers, Lifecycle Tiering/Expiry, and VNet Lockdown)

```hcl
app_name            = "orders"
environment         = "prod"
resource_group_name = "orders-prod"
location            = "eastus2"
principal_id        = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media = {
    cool_after_days = 30  # Move older images & videos to Cool storage after 30 days
    cold_after_days = 180
  }
  exports = {
    delete_after_days = 14 # Automatically expire generated reports/exports after 14 days
  }
}

# Lock storage firewall down to AKS and App Service subnets (with Microsoft.Storage service endpoints)
allowed_subnet_ids = [
  "/subscriptions/<sub-id>/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/aks-nodes",
  "/subscriptions/<sub-id>/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/appservice-integration",
]

enable_delete_lock = true
```

---

## Connecting from AKS & App Service

No connection strings or secrets are needed. Pass the `app_settings` output (`AZURE_STORAGE_BLOB_ENDPOINT` and `AZURE_STORAGE_ACCOUNT_NAME`) into your App Service configuration or AKS `ConfigMap`, and initialize the Azure Blob SDK with `DefaultAzureCredential`:

- **.NET**: `new BlobServiceClient(new Uri(endpoint), new DefaultAzureCredential())`
- **Python**: `BlobServiceClient(account_url=endpoint, credential=DefaultAzureCredential())`
- **Node.js / TypeScript**: `new BlobServiceClient(endpoint, new DefaultAzureCredential())`
- **Java**: `new BlobServiceClientBuilder().endpoint(endpoint).credential(new DefaultAzureCredentialBuilder().build()).buildClient()`
