# Standard Application Storage

The standard way an application team gets Azure Storage.

Give the module your application's name, environment and resource group. It creates one
hardened storage account that follows the organisation's conventions — private blob
containers, optional queues and file shares, access through your application's Entra ID
identity, and no unauthenticated network access. You do not need to know Azure Storage to
use this safely: fill in the obvious inputs and trust the module's judgment for the rest.

## Quickstart

```hcl
# main.tf — run with: tofu plan -var-file=dev.tfvars
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.0.0" }
    random  = { source = "hashicorp/random", version = ">= 3.5.0" }
  }
}

module "storage" {
  source = "<path to this module>"

  application         = "orders"
  environment         = "staging"
  resource_group_name = "orders-staging"      # your app's existing RG
  blob_containers     = ["uploads", "exports"]
  app_identity_object_ids = [var.app_identity_object_id]
}

output "blob_endpoint" { value = module.storage.blob_endpoint }
```

```hcl
# dev.tfvars
app_identity_object_id = "3f2c8a1e-9b4d-4a6e-8c1f-0d5e7a9b2c34"
```

Location is inherited from your resource group's region. If your environment is brand new
and the resource group does not exist yet, leave `resource_group_name` unset, set
`location`, and the module creates the conventional `orders-staging` group — that is what
`minimal.tfvars` demonstrates.

## The module's judgment (what it decides for you)

| Decision | Judgment | Why |
| --- | --- | --- |
| Account naming | `st` + app + environment + 4 random chars, e.g. `stordersstagingk7d2` | Storage account names must be globally unique, 3–24 lowercase alphanumerics. Ownership stays visible via tags. |
| Account kind | StorageV2, Standard tier, Hot | Covers blobs, queues and files; cheapest general-purpose tier. |
| Redundancy | LRS (override: `replication_type`) | Three replicas in one region is durable and cheapest for app data. |
| Authentication | Entra ID only; shared keys disabled (override: `shared_access_key_enabled`) | Your app already has an identity. No keys means no secret to leak, embed in a connection string, or rotate. |
| Public access | None — account unreachable from the internet | Apps on AKS/App Service reach storage via private endpoints. |
| Network | Deny-by-default firewall; private endpoints wired on request (`private_endpoint_subnet_id`) | Safe state until your VNet is connected. |
| Data access grants | Built-in roles for your identities: Storage Blob Data Contributor, plus Queue/File data roles when those are in use | Least-privilege data access, no manual role assignment steps. |
| Containers | Always private | Anonymous blob access is never appropriate for application data. |
| Encryption | HTTPS-only, TLS 1.2 minimum, infrastructure (double) encryption | Defence in depth at no cost. |
| Data protection | Blob versioning on, 7-day soft delete for blobs and containers | Accidental deletes/overwrites are recoverable. |
| Tagging | `application`, `environment`, `module`, `managed-by` on everything | Findable and chargeback-friendly; add your own via `additional_tags`. |

## How your application connects

1. Pass your identity's object ID(s) in `app_identity_object_ids` (the managed identity
   principal/object ID you can see on the identity in Entra ID). The module grants the
   data roles on the account.
2. Give the module the subnet your app runs in (`private_endpoint_subnet_id`). It creates
   private endpoints for blob — and for file/queue when you use them. If your platform
   team manages `privatelink.*.core.windows.net` DNS zones centrally you are done;
   otherwise pass them in `private_dns_zone_ids`.
3. In your application, address the account with its endpoint
   (`module.storage.blob_endpoint`) and authenticate with your identity — the Azure SDKs
   do this with `DefaultAzureCredential` / workload identity, no connection strings.

If you genuinely cannot use private endpoints yet, the sanctioned alternative is
`public_network_access_enabled = true` **plus** `allowed_subnet_ids` (service endpoints).
There is no "open to the internet" setting on purpose.

## Escape hatches

These exist for exceptions, not for everyday use — if you find yourself reaching for them,
talk to the platform team first:

- `shared_access_key_enabled = true` — for legacy SAS URLs or key-based mounts. Turn back
  off as soon as possible.
- `replication_type = "ZRS" | "GZRS"` — when availability requirements justify the cost.
- `blob_versioning_enabled = false` — for large, cheap-to-regenerate datasets.
- `public_network_access_enabled` / `allowed_subnet_ids` — see above.
- `additional_tags` — cost codes, team tags, anything your org needs.

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `application` | yes | App name, e.g. `orders`. |
| `environment` | yes | e.g. `staging`, `prod`. |
| `resource_group_name` | no* | Your app's existing resource group. *Unset ⇒ module creates `app-env` RG, then `location` is required. |
| `location` | no | Azure region; inherited from the resource group when unset. |
| `blob_containers` | no | e.g. `["uploads", "exports"]`. |
| `queues` | no | e.g. `["thumbnail-jobs"]`. |
| `file_shares` | no | Only if you need SMB shares. |
| `app_identity_object_ids` | no | Object IDs of the app's Entra identities. |
| `private_endpoint_subnet_id` | no | Subnet for private endpoints. |
| `private_dns_zone_ids` | no | Per-service privatelink zones, if self-managed. |
| `public_network_access_enabled`, `allowed_subnet_ids` | no | Service-endpoint escape hatch (default off). |
| `replication_type`, `blob_versioning_enabled`, `shared_access_key_enabled`, `additional_tags` | no | Judgment overrides. |

## Outputs

`account_name`, `account_id`, `resource_group_name`, `location`, `blob_endpoint`,
`queue_endpoint`, `file_endpoint`.

## Running it

Azure credentials come from the environment (`ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` and
client/OIDC credentials). `minimal.tfvars` is the smallest valid instantiation:

```
tofu plan -var-file=minimal.tfvars
```

Keep the module's state in your team's remote backend alongside the rest of the
application's infrastructure.
