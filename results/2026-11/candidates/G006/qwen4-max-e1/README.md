# Standard application storage module

The standard way for an application team to get Azure Blob storage. Copy the
example below, fill in the four required inputs, and the module takes care of
naming, security, redundancy and data protection for you.

## What you get

- A **StorageV2 / Standard / Hot** storage account inside your application's
  **existing resource group** (the module never creates or changes the group).
- **Entra ID-only data access**: storage account keys are disabled. Your app's
  existing identity (AKS workload identity or App Service managed identity) is
  granted **Storage Blob Data Contributor**. In code, use
  `DefaultAzureCredential` / managed identity with the blob endpoint output —
  no connection strings or keys to manage or rotate.
- **Private containers only** — no anonymous/public blob access, HTTPS only,
  TLS 1.2 minimum, double encryption at rest, no cross-tenant replication,
  no SFTP.
- **Accidental-loss protection**: blob versioning plus soft delete for blobs
  and containers (14 days in prod, 7 elsewhere).
- **Redundancy**: ZRS (survives a datacenter/zone failure) in `prod`, LRS in
  non-prod to keep costs down.
- A globally-unique name derived from your app + environment, and standard
  `app` / `environment` / `managed-by` tags.

## Example

```hcl
module "storage" {
  source = "./path/to/this/module" # or your registry/git reference

  app_name            = "orders"
  environment         = "prod"
  resource_group_name = "orders-prod"
  location            = "westeurope"

  # Containers for your app's files (all private):
  containers = ["uploads", "reports"]

  # Object (principal) ID of your app's managed identity:
  application_principal_ids = ["00000000-0000-0000-0000-000000000000"]

  # Optional extra tags:
  tags = {
    cost-center = "cc-1234"
  }
}
```

Then point your SDK at `module.storage.primary_blob_endpoint` and authenticate
with your managed identity. That's it.

## Inputs

| Name | Required | Default | Notes |
|------|----------|---------|-------|
| `app_name` | yes | — | 2–20 chars, lowercase letters/digits/hyphens |
| `environment` | yes | — | e.g. `dev`, `staging`, `prod` |
| `resource_group_name` | yes | — | your app's existing RG for this environment |
| `location` | yes | — | same region as the RG, e.g. `westeurope` |
| `containers` | no | `[]` | private blob containers to create |
| `application_principal_ids` | no | `[]` | identity **object IDs** (not client IDs) to grant blob read/write |
| `replication_type` | no | ZRS in prod, LRS otherwise | advanced override |
| `soft_delete_retention_days` | no | 14 in prod, 7 otherwise | advanced override |
| `storage_account_name_override` | no | generated | escape hatch, rarely needed |
| `tags` | no | `{}` | merged over the standard tags |
| `subscription_id` | no | from environment | `ARM_SUBSCRIPTION_ID` |

## Outputs

`storage_account_name`, `storage_account_id`, `primary_blob_endpoint`,
`container_names`, `container_ids`, `resource_group_name`, `location`.

## Notes

- The deploying principal needs Contributor (or Storage Account Contributor)
  on the resource group and User Access Administrator (or a scoped RBAC role)
  to create the role assignments.
- The network firewall defaults to open so AKS/App Service outbound traffic
  works with zero extra setup; every data request is still authenticated and
  authorized via Entra ID + RBAC. If your platform team later requires private
  endpoints, that can be layered on without changing your inputs.
