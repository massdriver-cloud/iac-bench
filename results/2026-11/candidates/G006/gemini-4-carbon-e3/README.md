# Application Storage Account Module (Azure)

Standard OpenTofu module for provisioning application file storage (user uploads, images and videos, generated reports, and exports) in Azure Blob Storage.

Designed for application teams running on **AKS** (Workload Identity) and **App Service** (Managed Identity): provide your `app_name`, `environment`, and `app_principal_id`, and the module handles naming, placement, Entra ID RBAC, encryption, data protection, and lifecycle cost optimization automatically.

---

## Quick Start (Minimal Example)

```hcl
app_name         = "orders"
environment      = "staging"
app_principal_id = "00000000-0000-0000-0000-000000000000" # Object ID of your app's Entra ID identity
```

This creates a hardened `StorageV2` account inside `orders-staging` (inheriting the resource group's Azure region and tags), provisions a private `files` blob container, grants your application identity `Storage Blob Data Contributor` and `Storage Blob Delegator`, and configures automated lifecycle management.

---

## Common Recipes

### Multiple Containers & Auto-Expiring Exports / Reports

```hcl
app_name         = "orders"
environment      = "prod"
app_principal_id = "00000000-0000-0000-0000-000000000000"

containers = {
  uploads = {}
  media   = {}
  exports = {
    delete_after_days = 30 # Automatically clean up generated CSV/PDF exports after 30 days
  }
}
```

### Direct Browser Uploads / Media Streaming (CORS + User Delegation SAS)

Because storage account shared keys are disabled, generate short-lived **User Delegation SAS** URLs in your backend using `DefaultAzureCredential` (`Storage Blob Delegator` is granted automatically) and allow your frontend origin:

```hcl
cors_rules = [
  {
    allowed_origins    = ["https://orders.example.com"]
    allowed_methods    = ["GET", "HEAD", "PUT", "OPTIONS"]
    max_age_in_seconds = 3600
  }
]
```

### VNet Firewall or Private Endpoint (AKS & App Service)

- **VNet Service Endpoints**: pass `allowed_subnet_ids` (e.g. AKS node/pod subnets and App Service VNet integration subnets); the storage firewall automatically switches to `Deny` by default for all other networks.
- **Private Link**: pass `private_endpoint_subnet_id` (and optional `private_dns_zone_ids`); the module creates a Blob Private Endpoint in your application's resource group and disables public network access by default.

---

## Connecting from Application Code (AKS & App Service)

Shared access keys and connection strings are **disabled**. Authenticate with `DefaultAzureCredential` from the Azure Identity SDK using the `blob_endpoint` (or `app_configuration`) module output:

- **`AZURE_STORAGE_BLOB_ENDPOINT`** (`output.blob_endpoint`): e.g. `https://stordersstagingfc205d4.blob.core.windows.net/`
- **`AZURE_STORAGE_ACCOUNT_NAME`** (`output.storage_account_name`): e.g. `stordersstagingfc205d4`

---

## Built-In Defaults & Design Decisions

| Concern | Non-Production (`dev`, `staging`, etc.) | Production (`prod`, `production`) |
|---|---|---|
| **Placement** | `<app_name>-<environment>` RG (region inherited) | `<app_name>-<environment>` RG (region inherited) |
| **Authentication** | Entra ID OAuth RBAC only (`shared_access_key_enabled = false`) | Entra ID OAuth RBAC only (`shared_access_key_enabled = false`) |
| **Public Access** | Anonymous blob/container access blocked | Anonymous blob/container access blocked |
| **Encryption** | HTTPS-only, TLS 1.2+, double infrastructure encryption | HTTPS-only, TLS 1.2+, double infrastructure encryption |
| **Redundancy** | `LRS` (cost-optimized) | `GZRS` (zone + regional DR durability) |
| **Soft Delete** | 7 days (blobs & containers) | 30 days (blobs & containers) |
| **Versioning & Change Feed** | Versioning enabled; versions retained 30 days | Versioning + Change Feed enabled; versions retained 90 days |
| **Tiering** | Hot -> Cool (30d unaccessed, auto-reheat) -> Cold (90d, online) | Hot -> Cool (30d unaccessed, auto-reheat) -> Cold (90d, online) |
