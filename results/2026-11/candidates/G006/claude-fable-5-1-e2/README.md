# Application storage account

The standard way an application team gets Azure Storage for the files its
application works with (user uploads, images and videos, generated reports and
exports). Copy the example, fill in three inputs, and the module makes every
other decision.

## Example

```hcl
application_name          = "orders"
environment               = "prod"
app_identity_principal_id = "<object ID of the orders app's managed identity>"
```

That creates, inside the existing `orders-prod` resource group:

- a `StorageV2` account named `stordersprod<random>` in the resource group's region
- private containers `uploads`, `media` and `exports`
- a *Storage Blob Data Contributor* role assignment for the app identity

The application then reads and writes blobs with `DefaultAzureCredential` and
the `primary_blob_endpoint` output. No keys, no connection strings.

## What the module decides for you

| Concern | Decision |
|---|---|
| Authentication | Entra ID only: shared keys disabled, OAuth default, RBAC grant to the app identity |
| Exposure | HTTPS only, TLS 1.2+, no anonymous blob access, no cross-tenant replication |
| Encryption | Microsoft-managed keys with infrastructure (double) encryption |
| Redundancy | `GRS` in `prod`/`production`, `LRS` everywhere else |
| Data protection | Blob versioning on; blob + container soft delete (30 days prod, 7 days otherwise) |
| Cost | Hot tier; files untouched for 90 days move to Cool; old versions pruned after the soft-delete window |
| Network | Open by default (AKS / App Service egress is not fixed); set `allowed_subnet_ids` / `allowed_ip_ranges` to lock it down |

Optional inputs (`containers`, `app_identity_role`, `replication_type`,
`allowed_subnet_ids`, `allowed_ip_ranges`, `cool_tier_after_days`, `tags`,
`resource_group_name`) exist for the cases where a team knows it needs
something different.
