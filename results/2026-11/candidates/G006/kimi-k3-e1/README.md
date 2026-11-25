# Standard application storage (Azure Storage Account)

The standard way for an application team to get blob storage for its
application (user uploads, images and videos, generated reports and exports,
...). Copy the example, fill in a handful of obvious inputs, and trust the
module for everything else.

## Usage

```hcl
# terraform.tfvars
app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "westeurope"

# Object ID of the app's managed identity / service principal
# (the *object* ID, not the app/client ID).
app_identity_principal_id = "11111111-1111-1111-1111-111111111111"

containers = ["uploads", "media", "reports"]
```

```sh
tofu init
tofu apply
```

`minimal.tfvars` in this repo is the smallest valid instantiation.

## What the application gets

* One general-purpose v2 storage account in the application's existing
  resource group (`Standard`, hot tier).
* The requested private blob containers.
* The application's Entra identity (workload identity on AKS, managed identity
  on App Service) is granted **Storage Blob Data Contributor** on the account.

The application connects with the `primary_blob_endpoint` output and its
identity (e.g. `DefaultAzureCredential` in the Azure SDKs). There are no
connection strings, account keys or SAS tokens to store or rotate.

## Decisions the module makes for you

| Area | Default | Why |
|---|---|---|
| Naming | `st<app><env><hash>` (e.g. `stordersstaginga1b2c3`) | Valid and effectively globally unique; stable per app/environment. Override with `name_override`. |
| Auth | Entra ID (RBAC) only; shared keys / SAS disabled | Identity-based access, nothing secret to leak. `shared_access_key_enabled = true` is the escape hatch for legacy clients. |
| Transport | HTTPS only, TLS 1.2+ | Baseline. |
| Anonymous access | Disabled, containers always private | Uploads and reports must never be public. |
| Data protection | Blob versioning, change feed, 7-day soft delete on blobs and containers | An accidental delete/overwrite is recoverable. Tune with `soft_delete_retention_days`. |
| Redundancy | LRS; ZRS in `prod` | Cost vs. resilience. Override with `account_replication_type`. |
| Encryption | Microsoft-managed keys + infrastructure (double) encryption | No key management burden. |
| Network | Public endpoint, firewall allows all | Apps on AKS/App Service reach it over TLS. Pass `network_allowed_subnet_ids` / `network_allowed_ip_rules` to lock down; the firewall default flips to `Deny` automatically. |
| Tags | `application`, `environment`, `managed-by` | Cost allocation and ownership. Add more via `tags`. |

Containers are created through the Azure control plane (ARM) rather than the
storage data plane, so provisioning works even with shared keys disabled and
the deploying identity needs no data-plane role on the account.

## Inputs

Required: `app_name`, `environment`, `resource_group_name`, `location`,
`app_identity_principal_id`.

Optional: `containers`, `account_replication_type`,
`soft_delete_retention_days`, `shared_access_key_enabled`,
`network_allowed_subnet_ids`, `network_allowed_ip_rules`, `name_override`,
`tags`. See `variables.tf` for full descriptions and validation rules.

## Outputs

`storage_account_id`, `storage_account_name`, `primary_blob_endpoint`,
`container_ids`, `resource_group_name`.
