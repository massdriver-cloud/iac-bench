# Standard application storage account

The standard way an application team gets Azure Storage for the files its app
stores and works with: user uploads, images and videos, generated reports and
exports. You fill in three obvious inputs; the module owns every other design
decision so every account comes out the same.

## Usage

```hcl
module "storage" {
  source = "<this module>"

  # What you decide:
  name                  = "stordersprod01"       # globally unique, 3-24 lowercase letters/digits
  resource_group_name   = "orders-prod"          # your app's existing resource group
  identity_principal_id = "<object ID of your app's Entra identity>"

  # Optional:
  containers = ["uploads", "media", "reports"]
  tags       = { application = "orders", environment = "prod" }
}

output "blob_endpoint" { value = module.storage.primary_blob_endpoint }
```

Your application (AKS or App Service) authenticates with its own identity via
`DefaultAzureCredential` / Workload Identity — the module grants it
**Storage Blob Data Contributor**. There are no access keys, SAS tokens or
connection strings to configure, store or leak.

## Decisions the module makes for you

| Decision | Value | Why |
| --- | --- | --- |
| Account kind / tier | StorageV2 / Standard | right default for application files |
| Replication | LRS (overridable to ZRS/GRS/...) | cheapest; durability is the one trade-off left to the team |
| Region | your resource group's region | storage belongs next to the app |
| Transport | HTTPS only, TLS 1.2+ | baseline hygiene |
| Authentication | Entra ID only — shared access keys disabled, OAuth default | keys/SAS are the #1 storage leak; your app already has an identity |
| Public blob access | disabled at the account level | application data is never public |
| Soft delete | 7 days on blobs and containers | accidental deletes are recoverable |
| Containers | created from a plain name list, all private | developers shouldn't touch data-plane details |
| Network | public endpoint reachable, Entra-authenticated | works from AKS and App Service with zero network plumbing |

## Inputs

| Name | Required | Default | Notes |
| --- | --- | --- | --- |
| `name` | yes | — | storage account name, validated |
| `resource_group_name` | yes | — | must already exist |
| `identity_principal_id` | yes | — | object ID of the app's identity |
| `location` | no | resource group's region | |
| `containers` | no | `[]` | blob container names |
| `account_replication_type` | no | `LRS` | |
| `tags` | no | `{}` | |

## Outputs

`id`, `name`, `primary_blob_endpoint`, `containers` (name → resource ID).

## Notes

- The resource group is created/owned elsewhere; this module never manages it.
- The principal running OpenTofu needs permission to create role assignments
  (e.g. Owner or User Access Administrator on the scope); it also receives
  Storage Blob Data Contributor so it can create the containers over the
  keyless data plane.
- File shares, queues and tables are intentionally out of scope for this
  standard module.
