# Application storage

The standard way an application team gets blob storage in Azure for the files
their application stores and works with: user uploads, images and video,
generated reports and exports.

Applications run on AKS and App Service and already have an Entra ID identity,
and every application already has its own resource group per environment
(e.g. `orders-staging`, `orders-prod`). This module turns those two facts into
a fully configured, secure, cost-managed storage account — you fill in three
things and trust the module's judgment for everything else.

## Quick start

```hcl
module "app_storage" {
  source = "git::https://git.example.com/platform/app-storage.git?ref=v1"

  # The application's resource group in this environment.
  resource_group_name = "orders-staging"

  # The identities the application authenticates with.
  # (AKS workload identity and/or App Service managed identity.)
  identity_object_ids = [
    azurerm_user_assigned_identity.orders_app.principal_id,
  ]

  # The containers the application works with.
  containers = [
    { name = "user-uploads" },
    { name = "generated-reports", lifecycle = { delete_after_days = 365 } },
  ]
}

# Wire the outputs into the application:
output "app_settings" {
  value = {
    AZURE_STORAGE_ACCOUNT_NAME = module.app_storage.storage_account_name
    AZURE_STORAGE_BLOB_ENDPOINT = module.app_storage.blob_endpoint
  }
}
```

That's it. Location comes from your resource group, the account name is
derived and made globally unique for you, and every other decision is
described below.

The smallest possible instantiation (what `minimal.tfvars` at the root of this
repository shows, and what CI plans with) is just the three required inputs:

```hcl
resource_group_name = "orders-staging"
identity_object_ids = ["<object id of the app's identity>"]
containers          = [{ name = "app-files" }]
```

## What the module decides for you

| Decision | Default | Why |
| --- | --- | --- |
| Account name | `st` + your resource group name + a random suffix, e.g. `stordersstaging3f9c2a1d` | Storage account names are global; you should never have to invent one, and two apps can never collide |
| Kind / tier | Standard general-purpose v2 (StorageV2) | The only kind that supports lifecycle management and the rest of the platform defaults; premium is a special case this module deliberately doesn't serve |
| Redundancy | **ZRS** | Survives a zone outage with no app changes, at a modest premium over LRS. Override with `replication_type` (GRS/GZRS for region-outage requirements, LRS for throwaway data) |
| Authentication | **Entra ID only** — account keys and key-signed SAS are disabled | Your pods and App Service already have identities; a second, shared, unattributable credential is pure risk |
| Authorization | `Storage Blob Data Contributor` on the account for every identity in `identity_object_ids` | Read/write/delete of blobs — the data-plane access apps need, nothing more |
| Transport | HTTPS only, TLS 1.2 minimum | Storage accepts plaintext TLS 1.0 by default; we don't |
| Public access | Blob anonymous access disabled at the account level; every container is private | Files are served through your application (or a CDN), never straight from the account |
| Network | Reachable over the public endpoint, authenticated by Entra ID | AKS and App Service egress addresses are not predictable; authentication is the control that matters. Lock down with `allowed_ip_ranges` / `allowed_subnet_ids`, or go private with a private endpoint |
| Data protection | Blob soft delete 7 days, container soft delete 7 days, blob versioning on | A wrong delete or overwrite is recoverable without a support ticket |
| Cost | Lifecycle: blobs move to Cool after 90 days; versions and snapshots are deleted after 180 days; blobs are never auto-deleted | Old uploads and reports cost about half as much at Cool; recoverable history can't be allowed to grow forever; automatic deletion only ever happens if you ask for it |
| Encryption | Platform-managed keys with infrastructure (double) encryption | Customer-managed keys are a platform-team decision, not an app-team one |
| Replication in / out | Cross-tenant object replication disabled | Your data stays in your tenant |

The account is tagged `managed-by = opentofu` (plus anything you pass in
`tags`) so it's easy to tell module-created accounts from hand-made ones as we
migrate off the old way.

## How your application connects

No connection strings, no keys. The app uses the storage account name with the
Azure SDK's default credential chain, which picks up the identity it's running
as:

```text
<container url>   https://stordersstaging3f9c2a1d.blob.core.windows.net/user-uploads
<account name>    stordersstaging3f9c2a1d        # AZURE_STORAGE_ACCOUNT_NAME
```

- **App Service / Functions**: enable the managed identity you passed to
  `identity_object_ids`. The SDK's `DefaultAzureCredential` finds it.
- **AKS**: use workload identity federation on the same user-assigned identity
  (the usual `azure-workload-identity` setup). Nothing changes here.
- **Temporary download links** (e.g. e-mailing a report): have the app mint a
  *user delegation* SAS with its identity — that works with keys disabled and
  is the only SAS flavour the platform supports.

## Inputs

### Required

| Name | Type | Description |
| --- | --- | --- |
| `resource_group_name` | string | The application's resource group in this environment. Everything is created inside it. |
| `identity_object_ids` | list(string) | Object (principal) IDs of the app's Entra ID identities. Each is granted `Storage Blob Data Contributor`. |
| `containers` | list(object) | One object per container: `name`, plus optional `lifecycle` (below). |

### Optional

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `location` | string | resource group's location | Region for the account; leave unset. |
| `account_name_prefix` | string | derived from the resource group | Override the readable part of the account name (a random suffix is always appended). |
| `replication_type` | string | `"ZRS"` | One of `LRS`, `ZRS`, `GRS`, `GZRS`, `RAGRS`, `RAGZRS`. |
| `allowed_ip_ranges` | list(string) | `[]` | IPv4 addresses/CIDRs that may reach the account. Any value switches the firewall to deny-by-default. |
| `allowed_subnet_ids` | list(string) | `[]` | Subnet IDs (with a `Microsoft.Storage` service endpoint) that may reach the account. Same deny-by-default switch. |
| `private_endpoint_subnet_id` | string | `null` | Create a private endpoint for the blob service in this subnet. |
| `private_dns_zone_id` | string | `null` | The platform team's `privatelink.blob.core.windows.net` zone to link into. Required with `private_endpoint_subnet_id`. |
| `public_network_access_enabled` | bool | `true` | Set `false` only for private-endpoint-only access. |
| `shared_access_key_enabled` | bool | `false` | Enable only for a legacy tool that cannot authenticate with Entra ID; plan its migration. |
| `subscription_id` | string | from environment | Only for pipelines that hop subscriptions. |
| `tags` | map(string) | `{}` | Extra tags on the storage account. |

### The `lifecycle` block per container

All day counts are whole days since the blob was **last modified**, and rules
never apply outside their own container (use `prefix` to scope inside one).

| Attribute | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | `false` turns lifecycle management off for the container. |
| `prefix` | — | Only manage blobs under this path prefix inside the container. |
| `cool_after_days` | 90 | Move blobs to the Cool tier. Dropped automatically when you set `archive_after_days`/`delete_after_days` without it. |
| `archive_after_days` | — (never) | Move blobs to the Archive tier (rarely-read, compliance-style data). |
| `delete_after_days` | — (never) | **Delete blobs.** Opt-in; Azure requires `cool < archive < delete`. |
| `delete_versions_after_days` | 180 | Delete old blob versions (the recoverable history created by overwrites). |
| `delete_snapshots_after_days` | 180 | Delete old blob snapshots. |

Examples:

```hcl
containers = [
  # Keep uploads forever, standard tiering.
  { name = "user-uploads" },

  # Reports are regenerated nightly and 90 days of history is plenty.
  {
    name      = "generated-reports"
    lifecycle = { delete_after_days = 90 }
  },

  # Exports are compliance data: cool at 30 days, archive at 180, never deleted.
  {
    name = "compliance-exports"
    lifecycle = {
      cool_after_days    = 30
      archive_after_days = 180
    }
  },

  # Raw video that only needs to survive 14 days before processing.
  {
    name      = "raw-video"
    lifecycle = { delete_after_days = 14, delete_versions_after_days = 14 }
  },

  # Hand-managed; no automatic tiering or cleanup at all.
  {
    name      = "hand-managed"
    lifecycle = { enabled = false }
  },
]
```

## Outputs

| Name | Description |
| --- | --- |
| `storage_account_name` | The account name your app connects with. |
| `storage_account_id` | Resource ID, e.g. for granting access elsewhere. |
| `blob_endpoint` | `https://<account>.blob.core.windows.net` |
| `containers` | Map of container name → `{ id, url }`. |
| `role_assignment_ids` | Map of identity object ID → role assignment ID. |
| `private_endpoint_id` | The blob private endpoint ID, or `null`. |

## Networking, in one paragraph

By default the account is reachable from anywhere over HTTPS — which is what
AKS and App Service need — and access control is Entra ID: only the identities
you list can read or write. To restrict by network as well, pass
`allowed_ip_ranges` and/or `allowed_subnet_ids` (the firewall then becomes
deny-by-default, so list *everything* that must reach the account, and note
AKS/App Service egress addresses are usually not static). To go fully private,
pass `private_endpoint_subnet_id` + `private_dns_zone_id` (the shared
`privatelink.blob.core.windows.net` zone is platform-owned) and set
`public_network_access_enabled = false`.

## FAQ

**Where did my account keys / connection string go?**
Disabled by design. If a tool genuinely can't do OAuth yet, set
`shared_access_key_enabled = true` as a stopgap — but tell the platform team.

**Can I make a container public so the app can serve images directly?**
Not with this module. Serve via the app or put a CDN in front of it — public
blob access is the footgun that created most of our past storage incidents.

**An important blob got deleted / overwritten.**
Within 7 days it's recoverable from soft delete; after that, blob versions
(kept 180 days by default) still hold the prior state. Restore with the
portal's "soft deleted" list or `az storage blob list --include v`-style SDK
calls — or ask #platform.

**I need Azure Files / a queue / a table.**
This module is deliberately blob-only; that's what uploads, media, reports and
exports are. Ask the platform team rather than hand-creating accounts.

**Premium / low-latency storage?**
Also deliberate: it's rarely the right answer and expensive. Talk to us.

**Why isn't the location an input I must set?**
Your resource group already lives in the right region; the module follows it.

**How do app teams consume this module?**
As a normal remote module (`source = "git::...?ref=v1"` — pin a tag!). The
repository itself also plans/applies directly as a root module for CI, using
`minimal.tfvars`, which is the smallest valid instantiation.

## Requirements

- OpenTofu (or Terraform) >= 1.6
- `hashicorp/azurerm` ~> 4.0, `hashicorp/random` ~> 3.6
- Azure credentials in the environment (`ARM_*` variables or an authenticated
  Azure CLI). When consumed as a child module, pass the provider through the
  `providers` meta-argument as usual.
