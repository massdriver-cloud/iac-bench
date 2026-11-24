# Standard Application Storage Account (OpenTofu Module)

Standard, opinionated Azure Storage Account configuration for application teams running on **AKS** and **App Service**.

## What This Module Gives You Out of the Box

- **Entra ID authentication only**: Shared access keys, anonymous/public blob access, and SFTP local users are disabled. Your application's Entra ID identity (`application_principal_id`) is automatically granted **Storage Blob Data Contributor** on the storage account.
- **Globally unique naming**: Automatically generates a valid 3–24 character lowercase alphanumeric name (`st<app><env><hash>`) so you never hit Azure naming restrictions.
- **Environment-aware resilience & data protection**:
  - **Production (`prod`, `production`)**: Geo-redundant storage (`GRS`), blob versioning enabled (non-current versions automatically expired after 90 days), and 30-day soft delete for blobs and containers.
  - **Non-production (`dev`, `staging`, `test`, `qa`, `uat`, `sandbox`)**: Locally redundant storage (`LRS`) and 7-day soft delete for blobs and containers.
- **Encryption & transport security**: HTTPS-only, TLS 1.2 minimum, infrastructure encryption enabled, and cross-tenant replication disabled.
- **Optional batteries included**: Private blob containers with per-container lifecycle rules (tier to Cool/Cold or auto-expire), CORS for browser direct uploads/downloads (via User Delegation SAS), VNet/IP firewall or Private Endpoint, and Log Analytics diagnostics.

## Quick Start

Copy `minimal.tfvars` (or expand with `containers`) and supply your app's details:

```hcl
application_name         = "orders"
environment              = "staging"
resource_group_name      = "orders-staging"
application_principal_id = "00000000-0000-0000-0000-000000000000"
location                 = "eastus2"

containers = {
  uploads = {}
  media   = {}
  reports = {
    lifecycle_tier_to_cool_after_days = 90
  }
  temp-exports = {
    lifecycle_delete_after_days = 14
  }
}
```

Run with OpenTofu:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

## Connecting From Your Application (AKS / App Service)

No connection strings or storage keys are needed (or allowed). Use the `primary_blob_endpoint` output with `DefaultAzureCredential` from the Azure SDK:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient(
    account_url="<primary_blob_endpoint output>",
    credential=DefaultAzureCredential(),
)
```
