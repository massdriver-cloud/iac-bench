# Standard Application Storage Account Module

A single, opinionated way for application teams to create the Azure storage their
app needs for user uploads, images, videos, generated reports, and exports.

Application developers should not need to know Azure Storage details. Copy the
example below, fill in the obvious values, and let the module handle the rest.

## Example

```hcl
module "app_storage" {
  source = "./" # or your git/registry location

  app_name            = "orders"
  environment         = "prod"
  resource_group_name = "orders-prod"
  location            = "eastus2" # optional; defaults to the resource group's region

  # The app's Entra ID identity (managed identity / service principal object ID).
  # It is granted "Storage Blob Data Contributor" on the account automatically.
  principal_id = "00000000-0000-0000-0000-000000000000"

  # Private blob containers the app needs.
  containers = ["uploads", "images", "videos", "reports", "exports"]
}
```

For AKS, pass the workload identity / kubelet identity object ID as
`principal_id`. For App Service, use the system-assigned or user-assigned
managed identity object ID. No connection strings or access keys are needed.

## What the module decides for you

| Concern | Default |
| --- | --- |
| Account kind / tier | General-purpose v2 (`StorageV2`), `Standard` |
| Replication | `GRS` in `prod`, `LRS` everywhere else |
| Transport security | HTTPS only, minimum TLS 1.2 |
| Public blob access | Disabled |
| Shared access keys | Disabled (Entra ID / RBAC only) |
| Data protection | Blob versioning, change feed, 7-day soft delete for blobs and containers |
| Naming | Globally-unique name generated from `app_name` and `environment` |
| Containers | Always private |

## Required inputs

- `app_name` – short application name, used in naming and tags.
- `resource_group_name` – the application's existing resource group.

Everything else has a safe default. Full list in `variables.tf`.

## Outputs

- `storage_account_id` – use in role assignments or other resource references.
- `storage_account_name`
- `primary_blob_endpoint`
- `container_names` / `container_ids`
- `primary_connection_string` (sensitive) – empty by default because access keys
  are disabled; enable `shared_access_key_enabled = true` only if you truly
  cannot use Entra ID.
