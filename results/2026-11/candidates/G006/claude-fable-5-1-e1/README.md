# app-storage

The standard way an application team gets Azure Storage for the files its
application stores and works with (user uploads, images, videos, generated
reports and exports).

## Quick start

Copy this, fill in the four values, run `tofu apply`:

```hcl
application_name         = "orders"
environment              = "staging"
resource_group_name      = "orders-staging"
application_principal_id = "<object ID of the orders app's managed identity>"
```

Everything else is decided by the module. You get:

- A general-purpose v2 storage account in your resource group, named
  `st<app><env><4 random chars>` (storage names are globally unique).
- Two private blob containers by default: `uploads` (files users give you) and
  `exports` (files you generate). Override with `containers = [...]`.
- Your application's identity granted **Storage Blob Data Contributor** on the
  account. In code, use `DefaultAzureCredential` / managed identity with the
  `primary_blob_endpoint` output - there are no keys or connection strings.

## What the module decides for you

| Concern | Decision |
| --- | --- |
| Authentication | Entra ID only. Shared keys and SAS are disabled; anonymous/public blobs are impossible. |
| Transport | HTTPS only, TLS 1.2 minimum. |
| Redundancy | `prod` -> zone-redundant (ZRS); other environments -> locally redundant (LRS). Override with `replication_type`. |
| Accidental deletion | Blob and container soft delete (30 days in prod, 7 otherwise) and blob versioning. Old versions/snapshots are expired automatically (90 days in prod, 30 otherwise). |
| Encryption | Microsoft-managed keys with infrastructure (double) encryption. |
| Network | Open by default so AKS/App Service workloads just work. Set `allowed_subnet_ids` and/or `allowed_ip_ranges` to lock the account down to those sources; Azure trusted services stay allowed. |
| Tags | `application`, `environment`, `managed-by`, `module`, plus anything in `tags`. |

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `application_name` | yes | Short app name, e.g. `orders`. |
| `environment` | yes | e.g. `dev`, `staging`, `prod`. |
| `resource_group_name` | yes | The app's existing resource group for this environment. |
| `application_principal_id` | yes | Object ID of the app's Entra ID identity. |
| `location` | no | Region, default `westeurope`. |
| `containers` | no | Container names, default `["uploads", "exports"]`. |
| `allowed_subnet_ids` | no | Subnets allowed to reach the account. |
| `allowed_ip_ranges` | no | Public IPs/CIDRs allowed to reach the account. |
| `replication_type` | no | Redundancy override. |
| `tags` | no | Extra tags. |

## Outputs

`storage_account_name`, `storage_account_id`, `resource_group_name`,
`primary_blob_endpoint`, `container_names`, `container_urls`.
