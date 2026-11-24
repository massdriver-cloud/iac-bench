# app-storage

The standard way an application team gets Azure Storage for its workload:
user uploads, images and videos, generated reports and exports.

One module call gives the application a correctly named, secured storage
account in its own resource group, the blob containers it asked for, and
data-plane access for its existing Entra ID identity — with every other
decision already made by the platform team.

## Usage

Copy this into your app's root module and fill in five values:

```hcl
module "storage" {
  source = "<platform module registry or git repo>/app-storage"

  app_name            = "orders"
  environment         = "staging"            # matches the resource group
  resource_group_name = "orders-staging"     # your app's own RG, must exist

  # Object (principal) ID of your app's Entra ID identity — for a
  # user-assigned managed identity, its Principal ID (not the client ID).
  identity_principal_id = "11111111-1111-1111-1111-111111111111"

  containers = ["uploads", "reports"]
}

# Hand the endpoint to your app (App Service setting, AKS env var, ...):
#   module.storage.primary_blob_endpoint
```

Your app code authenticates with its managed identity
(`DefaultAzureCredential` in the Azure SDKs) — no keys, no connection
strings, no secrets to rotate.

A ready-to-fill-in copy lives in [`minimal.tfvars`](./minimal.tfvars); it is
also the smallest valid instantiation of the module.

## What the module decides for you ("trust the module's judgment")

| Decision | Default | Why |
|---|---|---|
| Account kind / tier | StorageV2, Standard, Hot | Covers app file workloads at the lowest cost that keeps uploads and reports fast. |
| Naming | `st` + app + environment + 8-char uniqueness hash | Satisfies Azure's 3-24 char, lowercase, globally-unique naming rules; stable across plans. |
| Location | The resource group's region | Storage belongs next to the app; one less thing to know. |
| Transport | HTTPS only, TLS 1.2 minimum | Plain HTTP and old TLS are never acceptable. |
| Anonymous access | Disabled account-wide; all containers private | App data is never public. |
| App access | `Storage Blob Data Contributor` for the app's identity | Identity-based access from AKS / App Service; no keys in app config. |
| Shared keys | Enabled, but never output | See "Shared keys" below. |
| Soft delete | 7 days, blobs and containers | A bad deploy or bug that deletes files is recoverable. |
| Blob versioning | Off | Soft delete covers deletion; opt in if overwrites must be recoverable too. |
| Replication | LRS | Cheapest; consider `ZRS` for prod, GRS* if you need a secondary region. |
| Network | Public endpoint, HTTPS, Entra-ID-gated | Works from AKS and App Service with zero network plumbing; `var.network` adds a firewall if needed. |
| Tags | application, environment, managed-by, module + yours | Consistent cost/ownership reporting. |
| Encryption | Microsoft-managed keys (platform default) | CMK is a platform decision, not an app-team knob. |
| Secrets in outputs | None | Keys, connection strings and SAS are never exported. |

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `app_name` | `string` | Short app name (`orders`). 3-20 chars, lowercase alnum + hyphens. |
| `environment` | `string` | Environment (`staging`, `prod`). 2-12 lowercase alnum. |
| `resource_group_name` | `string` | The app's existing resource group. The module never creates or manages it. |
| `identity_principal_id` | `string` | Object (principal) ID of the app's Entra ID identity. |

### Optional

| Name | Type | Default | Description |
|---|---|---|---|
| `containers` | `set(string)` | `[]` | Private blob containers to create. |
| `location` | `string` | resource group's region | Override the region. |
| `storage_account_name` | `string` | generated | Override the generated name (rarely needed). |
| `replication_type` | `string` | `"LRS"` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS`, `RAGZRS`. |
| `access_tier` | `string` | `"Hot"` | `Hot` or `Cool`. |
| `blob_versioning_enabled` | `bool` | `false` | Keep old blob versions on overwrite. |
| `soft_delete_retention_days` | `number` | `7` | Recovery window for deleted blobs/containers (1-365). |
| `lifecycle_rules` | `list(object)` | `[]` | Cool/archive/delete blobs by age, e.g. expiring exports. |
| `shared_access_key_enabled` | `bool` | `true` | Disable account keys entirely (see below). |
| `network` | `object` | open over HTTPS | Firewall: `default_action`, `ip_rules`, `subnet_ids`. |
| `tags` | `map(string)` | `{}` | Extra tags, merged over the module's. |

## Outputs

| Name | Description |
|---|---|
| `storage_account_id` | Resource ID of the account. |
| `storage_account_name` | Account name. |
| `primary_blob_endpoint` | Blob endpoint for the app to use. |
| `containers` | Map of container name → `{ id, url }`. |
| `app_identity_role_assignment_id` | ID of the app's RBAC assignment. |

## Common recipes

Production account with zone redundancy and expiring exports:

```hcl
replication_type = "ZRS"
containers       = ["uploads", "reports"]

lifecycle_rules = [
  {
    name              = "expire-exports"
    prefixes          = ["reports/"]
    delete_after_days = 90
  },
  {
    name                       = "cool-old-uploads"
    prefixes                   = ["uploads/"]
    tier_to_cool_after_days    = 30
    tier_to_archive_after_days = 180
  },
]
```

Locked-down networking (only your VNet subnets reach the account):

```hcl
network = {
  default_action = "Deny"
  subnet_ids     = [module.network.aks_subnet_id, module.network.app_service_subnet_id]
}
```

## Shared keys

Applications always authenticate with their Entra ID identity — the module
grants it access and exports no keys or connection strings. Shared-key
authentication is left **enabled** on the account by default for exactly one
reason: OpenTofu itself provisions the blob containers over the storage data
plane, and that needs either key access or a data-plane role
(`Storage Blob Data Contributor`) for the *deploying* identity plus a
provider configured with `storage_use_azuread = true`. Once your deployment
pipeline has that, set `shared_access_key_enabled = false` to disable keys
entirely.

## Notes and limits

- The resource group and the Entra ID identity must already exist; both are
  owned by the application/platform, not by this module.
- RBAC propagation in Azure can take a few minutes; an app may need a moment
  before its first data-plane call succeeds after initial provisioning.
- ZRS/GZRS are not available in every Azure region — check before opting in.
- No SFTP, NFS, Data Lake (HNS), file shares, queues or tables: this module
  is deliberately scoped to blob storage for application files.

## Requirements

- OpenTofu / Terraform `>= 1.5`
- `hashicorp/azurerm` `~> 3.100`
- The applying identity needs management-plane rights on the resource group
  (Contributor) plus permission to create role assignments
  (e.g. Owner or User Access Administrator) to wire up the app's RBAC.
