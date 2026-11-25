# Standard Application Storage Account Module (Azure Blob Storage)

Reusable OpenTofu root module for provisioning standardized, secure-by-default Azure Storage accounts for application workloads running on **AKS** and **Azure App Service** (user uploads, images and videos, generated reports, and exports).

Application teams supply a few obvious inputs (application name, environment, existing resource group, region, Entra ID identity, and containers). The module handles naming, security hardening, Entra ID RBAC, data protection, lifecycle cost controls, and environment-appropriate resilience automatically.

---

## Quick Start

Copy `examples/basic-staging.tfvars` (or `minimal.tfvars`) and replace the placeholder values:

```hcl
application_name         = "orders"
environment              = "staging"
resource_group_name      = "orders-staging"
location                 = "eastus2"
application_principal_id = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media = {
    tier_to_cool_after_days = 90
  }
  reports = {
    delete_after_days = 30
  }
}
```

Plan and apply directly:

```bash
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

See `examples/production-private.tfvars` for a full production setup with Private Endpoints, browser direct-upload support, container-scoped RBAC, Azure Monitor audit logs, and Microsoft Defender malware scanning.

---

## Connecting from AKS or App Service

Shared account keys and connection strings are **disabled**. Applications authenticate automatically using their Entra ID identity (AKS Workload Identity or App Service Managed Identity) and the `primary_blob_endpoint` output:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient(
    account_url="<primary_blob_endpoint output>",
    credential=DefaultAzureCredential(),
)
```

For direct browser uploads of large images or videos without enabling shared keys, set `enable_user_delegation_sas = true` and configure `cors_rules`. Your application can then issue short-lived User Delegation SAS tokens via Entra ID.

---

## What the Module Decides for You

### Naming
Azure storage account names must be 3–24 lowercase alphanumeric characters and globally unique across all of Azure. The module automatically generates deterministic, readable names:

```text
st<app_name_up_to_13_chars><dev|tst|stg|prd><6_char_hash>
```

The 6-character suffix is derived from subscription ID, resource group, application name, and environment.

### Security Baseline (Always Enforced)
- **Entra ID authentication only**: `shared_access_key_enabled = false`, `default_to_oauth_authentication = true`.
- **Least-privilege RBAC**: Grants `Storage Blob Data Contributor` to `application_principal_id` (no control-plane `Owner`/`Contributor` roles). Additional principals can be scoped to a single container.
- **No anonymous public blobs**: `allow_nested_items_to_be_public = false`, all containers created with `container_access_type = "private"`.
- **Encryption in transit and at rest**: `https_traffic_only_enabled = true`, `min_tls_version = "TLS1_2"`, and double encryption at rest (`infrastructure_encryption_enabled = true`).
- **Reduced attack surface**: SFTP, local users, NFSv3, hierarchical namespace, and cross-tenant replication are disabled.
- **Zero-trust network perimeter**: Storage firewall defaults to `Deny` (allowing trusted Azure services). Supply `private_endpoint` (which also disables public network access automatically) or `allowed_subnet_ids` for AKS/App Service VNet connectivity.

### Environment-Aware Resilience & Data Protection

| Setting | `dev` / `test` | `staging` | `prod` | Override Variable |
| --- | --- | --- | --- | --- |
| Redundancy | `LRS` | `ZRS` | `GRS` | `replication_type` |
| Blob soft delete | 7 days (permanent delete off) | 7 days (permanent delete off) | 30 days (permanent delete off) | `blob_soft_delete_days` |
| Container soft delete | 7 days | 7 days | 30 days | `container_soft_delete_days` |
| Blob versioning | Enabled | Enabled | Enabled | `versioning_enabled` |
| Old version auto-cleanup | 30 days | 30 days | 90 days | `noncurrent_version_retention_days` |
| Change feed | Disabled | Disabled | Enabled (30 days) | *(automatic with PITR/prod)* |
| Point-in-time restore | Disabled | Disabled | Enabled (7 days) | `point_in_time_restore_days` |
| `CanNotDelete` lock | Disabled | Disabled | Enabled | `enable_delete_lock` |

### Lifecycle Cost Controls
- Previous (noncurrent) blob versions are automatically expired after 30 days (non-prod) or 90 days (prod) so overwrite protection never causes unbounded storage bills.
- Active blobs remain in the `Hot` tier by default (avoiding surprise Cool-tier early-deletion or read fees), while per-container `tier_to_cool_after_days`, `tier_to_archive_after_days`, and `delete_after_days` let teams configure tiering or expiration in one line.

---

## Inputs

### Required
| Name | Description |
| --- | --- |
| `application_name` | Short lowercase application name (2–32 chars, letters/numbers/hyphens). |
| `environment` | One of `dev`, `test`, `staging`, `prod`. |
| `resource_group_name` | Name of the application's existing resource group (e.g., `orders-staging`). |
| `location` | Azure region matching the application's resource group (e.g., `eastus2`). |
| `application_principal_id` | Entra ID object ID of the application's Managed Identity or Service Principal. |
| `containers` | Map of blob container names to optional lifecycle settings (`tier_to_cool_after_days`, `tier_to_archive_after_days`, `delete_after_days`). |

### Optional Highlights
- **Access**: `application_role`, `enable_user_delegation_sas`, `additional_role_assignments` (supports account-wide or container-scoped RBAC).
- **Networking**: `private_endpoint`, `allowed_subnet_ids`, `allowed_ip_ranges`, `public_network_access_enabled`, `network_default_action`, `network_bypass`.
- **Data Protection & Lifecycle**: `replication_type`, `access_tier`, `blob_soft_delete_days`, `container_soft_delete_days`, `versioning_enabled`, `point_in_time_restore_days`, `noncurrent_version_retention_days`, `enable_delete_lock`, `additional_lifecycle_rules`, `cors_rules`.
- **Observability & Governance**: `log_analytics_workspace_id`, `enable_malware_scanning`, `malware_scanning_cap_gb_per_month`, `name_suffix`, `owner`, `cost_center`, `tags`.

---

## Outputs

| Name | Description |
| --- | --- |
| `storage_account_id` | ARM resource ID of the storage account. |
| `storage_account_name` | Generated Azure-compliant storage account name. |
| `primary_blob_endpoint` | HTTPS Blob endpoint URL for Azure SDK clients. |
| `primary_blob_host` | Blob endpoint hostname. |
| `container_names` | Sorted list of created blob container names. |
| `container_ids` | Map of container name to ARM resource ID. |
| `container_urls` | Map of container name to full HTTPS container URL. |
| `private_endpoint_id` | ARM resource ID of the Private Endpoint (or `null`). |
| `private_endpoint_ip_address` | Private IP address of the Private Endpoint (or `null`). |
| `effective_configuration` | Summary of all resolved security, resilience, and lifecycle settings. |
