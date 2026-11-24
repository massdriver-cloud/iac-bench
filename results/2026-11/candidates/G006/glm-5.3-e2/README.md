# Standard application storage

This module is the standard way an application team gets Azure storage.

Applications run on AKS and App Service, already have their own Entra ID
identity, and already have their own resource group per environment
(`orders-staging`, `orders-prod`). This module creates the storage account
that belongs in that resource group and configures it the way the platform
expects storage to be configured.

You decide **two** things: which application this is for, and which resource
group it lives in. The module owns every other decision (see
[What you get](#what-you-get)). If a default is genuinely wrong for your
application, the [escape hatches](#escape-hatches) are variables — never edits
to the module.

## Quick start

1. Put this module in your application's infrastructure repository (copy the
   files or vendor the repo as a subtree).
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in the first
   two lines.
3. Run:

   ```sh
   tofu init
   tofu plan
   tofu apply
   ```

A typical `terraform.tfvars` — this is all most teams ever write:

```hcl
name                = "orders"          # your application's name
resource_group_name = "orders-staging"  # the resource group your app lives in

principal_id = "6a1d3a2f-..."           # object ID of your app's Entra ID identity

containers = ["uploads", "media", "reports"]
```

To roll the same application out to production, change exactly one line
(`resource_group_name = "orders-prod"`). Storage account names are derived
deterministically from the application and resource group, so environments
never collide and nobody ever has to invent a globally-unique name. The
region comes from your resource group, so you don't have to look it up.

## What you get

| Area | The module's decision |
| --- | --- |
| Naming | `st` + application name + a 6-character hash of (application, resource group). Globally unique, deterministic, re-runnable. |
| Shape | General-purpose v2, standard performance, hot access tier — the right default for uploads, images and videos, reports and exports. |
| Replication | LRS in non-production, ZRS in production (read from your resource group name, since that is the platform's environment signal). Overridable to GRS/GZRS. |
| Authorization | **Entra ID only.** Shared keys, connection strings, SAS tokens and local users are disabled, and the account defaults to OAuth for unauthenticated requests. Your app's identity is granted `Storage Blob Data Contributor` (and `Storage File Data SMB Share Contributor` when you use file shares) — data-plane access only, no management rights. |
| Transport | HTTPS only, TLS 1.2 minimum, and anonymous/public blob access is impossible. |
| Encryption | Platform-managed keys with infrastructure (double) encryption enabled. |
| Blob data protection | Soft delete 7 days for blobs *and* containers, blob versioning on, versions and snapshots expire after 30 days. |
| Cost control | Block blobs untouched for 30 days tier to Cool. **Base blobs are never auto-deleted** — when application data may be destroyed is an application decision, not a platform one. |
| Files | Opt-in SMB shares with a quota you pick, for the few consumers that really need a file share. |
| Networking | Public endpoint that is *authenticated-only* by default; opt into IP rules, service-endpoint subnets, or full private endpoints with DNS. |
| Observability | Opt-in metrics and data-plane audit logs (read/write/delete) to a Log Analytics workspace. |
| Tags | `application = <name>` is always applied; add more via `tags`. |

## How your application uses the storage

The whole point of the module: your app already has an identity, and that is
the only credential it needs.

### AKS

- Run your pods with workload identity federation. The object ID you passed
  as `principal_id` is the workload (managed) identity's object ID — the same
  identity the pod federates as.
- Use the standard Azure SDK credential chain (`DefaultAzureCredential`) —
  no connection string, no key, no SAS. Point the SDK at the module's
  `storage_account_name` / `blob_endpoint` output.
- To mount storage as a volume, prefer the Blob CSI driver; the Azure Files
  (SMB) CSI driver authenticates with the storage account key, which this
  module disables by default (see `allow_shared_key_access` below).

### App Service

- Your App Service's system-assigned (or user-assigned) managed identity is
  what you pass as `principal_id`.
- Same story from application code: `DefaultAzureCredential`, the account
  name and the endpoint — nothing secret to put in app settings.
- Mounting an Azure Files share into App Service is the one mainstream
  feature that needs the account key today. If you need it, request a share
  via `file_shares` and set `allow_shared_key_access = true`; the module will
  still grant your identity the SMB share role for everything else.

### Azure Files, if you really need it

`file_shares = { content = 100 }` creates an SMB share with a 100 GiB quota.
Files are the exception, not the rule: blobs are cheaper, scale better and
work with Entra ID alone. Ask for a share only for content mounts or legacy
tools that speak SMB.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | — (**required**) | Application name; drives the storage account name and the `application` tag. |
| `resource_group_name` | string | — (**required**) | The application's resource group (e.g. `orders-staging`). Everything is created here. |
| `location` | string | `null` | Azure region. Omit to look it up from the resource group. |
| `containers` | set of string | `["uploads"]` | Blob containers to create, named after what the app stores. Private, Entra ID only. |
| `file_shares` | map of number | `{}` | File share name → quota in GiB. Opt-in SMB shares. |
| `principal_id` | string | `null` | Object ID of the app's Entra ID identity; grants it the data-plane roles it needs. |
| `replication_type` | string | `null` | `LRS`/`ZRS`/`GRS`/`GZRS`. Omit for ZRS in prod, LRS elsewhere. |
| `allow_shared_key_access` | bool | `false` | Re-enable key/SAS auth — only for key-based SMB mounts. |
| `public_network_access_enabled` | bool | `null` | Omit: enabled unless private endpoints are configured. |
| `allowed_ip_cidrs` | list of string | `[]` | Public IP ranges allowed; any entry makes the default action Deny. |
| `allowed_subnet_ids` | list of string | `[]` | Subnet IDs allowed via service endpoints; any entry makes the default action Deny. |
| `private_endpoint_subnet_id` | string | `null` | Subnet for private endpoints; creates blob+file endpoints, privatelink DNS zones and VNet links, and disables public access. |
| `log_analytics_workspace_id` | string | `null` | Send metrics and data-plane audit logs here. |
| `tags` | map of string | `{}` | Extra tags merged onto all resources. |

## Outputs

| Name | Description |
| --- | --- |
| `storage_account_id` | Resource ID of the storage account. |
| `storage_account_name` | The derived account name — this is what your SDK uses. |
| `location` | Region the account was created in. |
| `replication_type` | Replication actually configured (default or override). |
| `blob_endpoint` | `https://<account>.blob.core.windows.net/`. |
| `file_endpoint` | Azure Files endpoint (SMB and REST). |
| `container_names` | Blob containers created. |
| `file_share_names` | File shares created (empty unless requested). |
| `app_identity_role_assignment_ids` | Role assignments granted to the app identity. |
| `private_endpoint_ids` | Private endpoints by service (empty unless requested). |

Deliberately **not** output: access keys or connection strings. They don't
exist while shared-key access is disabled, and applications shouldn't use
them anyway.

## Escape hatches

| If you need… | Set… | What it trades away |
| --- | --- | --- |
| Cross-region durability | `replication_type = "GRS"` (or `GZRS`) | Cost; failover is manual for GRS. |
| Key-based SMB mounts (AKS CSI / App Service content) | `file_shares` + `allow_shared_key_access = true` | Entra-only auth for that account — keys and SAS become possible again. |
| Lock down the public endpoint | `allowed_ip_cidrs` and/or `allowed_subnet_ids` | Any source not listed is refused. |
| Fully private access | `private_endpoint_subnet_id` | Public endpoint disabled; your workload's subnet must host/see the endpoints. |
| Region pinning | `location` | Usually unnecessary — the resource group already pins you. |
| Audit trail | `log_analytics_workspace_id` | Log Analytics ingestion cost. |

Everything else (naming, tiering, soft delete, versioning, TLS, HTTPS,
blob-public-access, infrastructure encryption, RBAC role choice) is a
platform decision on purpose. If it's wrong, talk to the platform team about
changing the module for everyone rather than forking it.

## Deliberately out of scope

- **Queues and tables** — this module is for the files an application stores.
  Storage queues/tables are a separate, smaller need; ask the platform team.
- **Premium, NFS, or hierarchical-namespace (ADLS Gen2) accounts** — special
  shapes for special workloads; not the standard app-team default.
- **Customer-managed keys** — requires key vault policy decisions above the
  application team.
- **Auto-deletion of application data** — the lifecycle policy tiers and
  prunes *versions*, but never deletes live blobs.

## Notes for the platform team

- The module is applied as a root module from each application's repo; it
  contains its own `provider "azurerm"` block, so credentials come from the
  environment (as usual: `ARM_SUBSCRIPTION_ID` and friends).
- Private DNS zones (`privatelink.blob|file.core.windows.net`) are created in
  the application's resource group, so the module stays self-contained. If a
  central-zone convention is introduced later, migrate by importing.
- Provider data-plane operations use Entra ID (`storage_use_azuread = true`),
  consistent with the accounts themselves being key-less.
