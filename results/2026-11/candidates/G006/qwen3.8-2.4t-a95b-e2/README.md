# Standard application storage (Azure)

The standard way for an application team to get an Azure storage account for
its application's files: user uploads, images and videos, generated reports
and exports. Copy this module, fill in three values, and let the module's
judgment handle the rest.

## Usage

Fill in the three obvious inputs (copy `minimal.tfvars`):

```hcl
application = "orders"
environment = "staging"
location    = "westeurope"

# Optional - only if you want them:
# blob_containers          = ["uploads", "media", "reports"]
# app_identity_principal_ids = ["<principal ID of the app's managed identity>"]
```

Then:

```console
tofu init
tofu plan  -var-file minimal.tfvars
tofu apply -var-file minimal.tfvars
```

## What the module decides for you

| Decision | Judgment |
| --- | --- |
| Account name | `st<application><environment>` (e.g. `stordersstaging`) - deterministic, lowercase alphanumeric, within Azure's 24-char limit. |
| Placement | The application's own resource group, `<application>-<environment>` by default; override with `resource_group_name`. |
| Account shape | StorageV2, Standard tier, Hot access tier. |
| Replication | ZRS (zone-redundant) for environments starting with `prod`, LRS otherwise. Override with `replication_type`. |
| Transport security | TLS 1.2 minimum, HTTPS-only traffic. |
| Authentication | Entra ID only: shared access keys are **disabled** by default. The application's identities get the built-in **Storage Blob Data Contributor** role via `app_identity_principal_ids`. This is how AKS workload identity and App Service managed identity reach the account. |
| Public access | No anonymous access to blobs or containers is possible. |
| Encryption | Microsoft-managed keys plus infrastructure (double) encryption at rest. |
| Data protection | 7-day soft delete for blobs and containers. |
| Containers | Every container in `blob_containers` is created private; access is granted per identity, never via container ACLs. |
| Tags | `application`, `environment`, `managed_by = "opentofu"`, merged with your `tags`. |

## Requirements

* OpenTofu >= 1.6
* Azure credentials from the environment (`az login` or `ARM_*`/`AZURE_*`
  variables) and permission to create storage accounts and role assignments
  in the application's resource group.
* Storage account names are globally unique. If `st<app><env>` is already
  taken by someone outside your organisation, shorten the names - the module
  fails fast rather than guessing a new name.
* When adding `blob_containers`, the identity running OpenTofu needs a blob
  data role on the account (containers are managed over the data plane).
  Give it the same `app_identity_principal_ids` treatment, or temporarily
  set `shared_access_key_enabled = true` if your tooling requires keys.

## Outputs

`storage_account_name`, `storage_account_id`, `primary_blob_endpoint`,
`resource_group_name`, `blob_containers`.
