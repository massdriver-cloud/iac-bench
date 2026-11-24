# Standard Application Storage Account Module

Opinionated OpenTofu module for provisioning standardized Azure Storage Accounts for application workloads (user uploads, images/videos, generated reports, and exports) running on AKS and App Service.

## Quick Start

Copy this minimal configuration and supply the four inputs for your application:

```hcl
application_name          = "orders"
environment               = "staging"
resource_group_name       = "orders-staging"
app_identity_principal_id = "11111111-1111-1111-1111-111111111111"
```

Connect from your AKS or App Service application using the `primary_blob_endpoint` output and Entra ID (`DefaultAzureCredential` / Managed Identity) — no connection strings or storage keys required.

## Example with Custom Containers & Lifecycle Rules

```hcl
application_name          = "orders"
environment               = "prod"
resource_group_name       = "orders-prod"
app_identity_principal_id = "11111111-1111-1111-1111-111111111111"

containers = {
  uploads = {}
  media   = { cool_after_days = 90 }
  reports = { cool_after_days = 30, expire_after_days = 365 }
}

cors_allowed_origins = ["https://orders.example.com"]
```

## Design Decisions & Defaults

- **Passwordless Entra ID Authentication**: Shared access keys (`shared_access_key_enabled = false`), SFTP, and local users are disabled. Your application's Entra ID identity is automatically granted `Storage Blob Data Contributor` on the storage account.
- **Private by Default**: Public anonymous blob/container access is disabled (`allow_nested_items_to_be_public = false`), and every container is created with `private` access.
- **Transport & Encryption**: HTTPS-only (`TLS 1.2` minimum) and infrastructure double encryption (`infrastructure_encryption_enabled = true`) are enforced.
- **Globally Unique Naming**: Automatically generates a valid 3–24 character lowercase alphanumeric name (`st<app><env><random>`) so developers never hit Azure naming rules or collisions.
- **Environment-Aware Protection**:
  - `prod`: Geo-redundant storage (`GRS`), 30-day blob & container soft delete.
  - Non-prod (`dev`, `test`, `staging`): Locally redundant storage (`LRS`), 7-day blob & container soft delete.
- **Safe Versioning & Cost Control**: Blob versioning is enabled by default, paired with an automatic lifecycle policy that cleans up noncurrent versions after 30 days.
- **Optional Network Lockdown**: Supply `allowed_subnet_ids` / `allowed_ip_ranges` to turn on the storage firewall (default deny), or `private_endpoint_subnet_id` to provision a Private Endpoint and disable public network access entirely.
