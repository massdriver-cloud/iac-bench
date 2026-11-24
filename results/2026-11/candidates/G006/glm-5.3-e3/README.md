# Standard storage account for application files

The standard way an application team gets storage for the files its
application stores and works with: user uploads, images and video, generated
reports and exports.

The module assumes what is already true for our applications: the app runs on
AKS and/or App Service, it already has its own identity in our Entra ID
tenant, and it already has its own resource group in each environment
(`orders-staging`, `orders-prod`, ...). You fill in four inputs; the module
decides everything else.

## Quick start

```hcl
module "files" {
  source = "<this module>" # your git / module registry location

  name                    = "orders"
  resource_group_name     = "orders-staging"
  environment             = "staging"
  app_identity_object_ids = [azurerm_user_assigned_identity.orders.principal_id]
}
```

Your application now has:

- a storage account in its own resource group, in the resource group's region
  (override with `location` if you ever need to),
- the blob containers `uploads`, `media` and `exports` (override with
  `containers`),
- `Storage Blob Data Contributor` for the app identity - read, write and
  delete access to the blobs in every container.

Point the application at it by name - there is no connection string, because
the account has no usable keys:

```text
account: <module output> storage_account_name
endpoint: <module output> blob_endpoint
auth:     the app's managed identity (App Service) / workload identity (AKS),
          via DefaultAzureCredential (or the equivalent in your SDK)
```

`minimal.tfvars` in this repository is the same thing as a complete, runnable
example of the module used directly as a root module.

## What the module creates

| Resource | Purpose |
| --- | --- |
| `azurerm_storage_account` | general-purpose v2, Standard performance, Hot tier, replication per environment |
| `azurerm_storage_container` | one per entry in `containers`, all private |
| `azurerm_role_assignment` | `Storage Blob Data Contributor` for each identity in `app_identity_object_ids` |
| `azurerm_storage_blob_properties` | 14-day soft delete for blobs and containers, blob versioning |
| `azurerm_storage_management_policy` | Cool tiering for untouched blobs, cleanup of old versions |
| `azurerm_private_endpoint` (+ private DNS zone, VNet links) | only when `private_endpoint_subnet_ids` is set |

## What the module decides for you

| Decision | Value | Why |
| --- | --- | --- |
| Account name | `st<app><env><hash>`, derived from name + resource group | must be globally unique across Azure; deterministic means no surprises and no random suffix churn |
| Account kind / tier | StorageV2, Standard, Hot | the right shape and price for app files; premium / ADLS Gen2 / SFTP are different products with different needs - talk to the platform team if you need those |
| Replication | GRS in prod, LRS in dev/test/staging | prod uploads survive a regional outage; non-prod data does not justify the bill (override: `replication_type`) |
| Access model | Entra ID only: no account keys, no SAS, no public blobs | the apps already have identities; keys and SAS are standing credentials that bypass Entra ID (escape hatch: `allow_shared_key_access`) |
| Transport | HTTPS only, TLS 1.2 minimum | anything less is unauthenticated with 2025-era standards |
| Accidental deletion | 14-day soft delete for blobs and containers, blob versioning, versions kept 90 days | "someone overwrote the file" and "someone deleted the container" should be a non-event |
| Lifecycle | blobs untouched 90 days -> Cool tier; never auto-delete | pays for itself on media and old exports; auto-deleting application data is not a decision the module makes for you (opt in via `blob_lifecycle`) |
| Network | public endpoint by default (still requires Entra ID), automatically locked to private endpoints when you give subnets | apps on plain AKS/App Service just work; VNet-integrated apps get private access with one input |
| Tagging | `application`, `environment`, `managed-by` + your `tags` | cost tracking per app without per-team effort |

## Inputs

### Required

| Name | Type | Notes |
| --- | --- | --- |
| `name` | string | app/workload name, 3-24 chars, lowercase letters, digits, hyphens, e.g. `orders` |
| `resource_group_name` | string | the app's resource group for this environment; must already exist |
| `environment` | string | `dev`, `test`, `staging` or `prod` |
| `app_identity_object_ids` | set of string | object IDs of the app's Entra ID identities (managed identity / workload identity); each gets `Storage Blob Data Contributor` |

### Optional

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `location` | string | resource group's region | only set if the account must sit elsewhere |
| `containers` | set of string | `["uploads", "media", "exports"]` | blob containers to create |
| `replication_type` | string | GRS in prod, LRS elsewhere | `LRS`/`ZRS`/`GRS`/`RAGRS`/`GZRS` |
| `allow_shared_key_access` | bool | `false` | only for tooling that cannot use Entra ID |
| `allowed_ip_ranges` | list of string | `[]` | public IP/CIDR allow-list; empty = anywhere, still authenticated |
| `public_network_access_enabled` | bool | null (auto) | auto: off when private endpoints are used |
| `private_endpoint_subnet_ids` | list of string | `[]` | subnets for blob private endpoints |
| `private_dns_zone_id` | string | null | existing `privatelink.blob.core.windows.net` zone; otherwise the module manages one |
| `blob_lifecycle` | object | see `variables.tf` | `{ days_to_cool, days_to_archive, days_to_delete, days_to_keep_versions }` |
| `tags` | map of string | `{}` | extra tags on all resources |

## Outputs

| Name | Notes |
| --- | --- |
| `storage_account_id` | ARM resource ID |
| `storage_account_name` | account name for SDK settings |
| `location` | region the account ended up in |
| `blob_endpoint` | `https://<account>.blob.core.windows.net/` |
| `container_names` | the containers that were created |
| `private_dns_zone_id` | private DNS zone in use (null without private endpoints) |
| `private_endpoint_ids` | private endpoints, keyed by subnet index |

## Private networking

For apps that run inside a virtual network:

```hcl
module "files" {
  source = "<this module>"

  name                    = "orders"
  resource_group_name     = "orders-prod"
  environment             = "prod"
  app_identity_object_ids = [azurerm_user_assigned_identity.orders.principal_id]

  private_endpoint_subnet_ids = [azurerm_subnet.storage.id]
}
```

The public endpoint switches off automatically, a private endpoint is created
in the subnet, and the account's DNS name resolves privately inside the
linked VNets. If the organisation already runs a central
`privatelink.blob.core.windows.net` zone, pass its ID in `private_dns_zone_id`
and the module registers there instead of creating its own zone.

## Notes for application teams

- **No keys by design.** Use `DefaultAzureCredential` (or your SDK's
  equivalent) with the app's managed identity. If legacy tooling truly needs
  account keys, `allow_shared_key_access = true` is the escape hatch - expect
  to be asked why.
- **Role assignments take a few minutes** to become active after the first
  apply; a 403 right after deployment usually means "wait a moment", not
  "broken".
- **Local development:** run `az role assignment create --assignee <your user>
  --role "Storage Blob Data Contributor" --scope <storage_account_id>` to read
  the data with your own `az login` credentials.
- **Need a second account for the same app** (e.g. `orders-media`)? Call the
  module again with a different `name` - names won't collide.
- **Blob only.** Queues, tables and file shares are separate products; if your
  app needs one, that is a conversation with the platform team, not this
  module.
- **Deletion is protected, not prevented.** `tofu destroy` will really delete
  the account; soft delete and versioning only help for 14 days afterwards.
