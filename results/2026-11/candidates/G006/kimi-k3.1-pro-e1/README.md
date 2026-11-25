# Application storage account

A convention-based Azure Storage module for applications running on AKS or App Service. It creates one general-purpose v2 blob storage account in the application's existing resource group, private containers, and one data-plane role assignment for the application's existing Entra ID identity.

## What an application team supplies

Only four values are required:

| Input | What to use |
| --- | --- |
| `application_name` | A short workload name such as `orders`. |
| `resource_group_name` | The application's existing resource group, such as `orders-staging`. |
| `location` | The application's Azure region, such as `eastus`. |
| `application_identity_principal_id` | The **principal/object ID** of its managed identity or service principal. This is not the client ID. |

The smallest configuration is in [`minimal.tfvars`](./minimal.tfvars), and a copyable configuration is in [`examples/basic/main.tf`](./examples/basic/main.tf).

```hcl
module "application_storage" {
  source = "./modules/application-storage" # adjust to where this module is kept locally

  application_name                  = "orders"
  resource_group_name               = "orders-staging"
  location                          = "eastus"
  application_identity_principal_id = "11111111-1111-1111-1111-111111111111"

  container_names = ["uploads", "media", "reports"]
}
```

Use the `storage_account_name`, `primary_blob_endpoint`, and `containers` outputs to configure the application. Authenticate Azure SDK clients with the application's workload/managed identity (for example, `DefaultAzureCredential`). Do not use an account key or a connection string. New Entra ID role assignments can take a few minutes to propagate.

## Decisions made by the module

- **Naming:** deterministic, lowercase, globally unique-by-convention names. The readable application prefix is combined with a hash of subscription, resource group, and application. No random suffix changes between plans. `storage_account_name` is an escape hatch for an existing naming standard.
- **Data model:** standard StorageV2, hot-tier block blobs and private containers. One `files` container is created by default; set `container_names` to an empty set if only the account is wanted.
- **Application authorization:** the identity receives **Storage Blob Data Contributor** at the account scope. This permits container/blob read, write, and delete but not account administration, network changes, or key retrieval. The module never returns account keys.
- **Authentication and transport:** shared-key access is disabled, OAuth is the portal default, anonymous blob access is disabled, HTTPS is required, and TLS 1.2 is the minimum. SFTP, NFS, hierarchical namespace, and local users are disabled because application file workloads do not need them.
- **Protection:** blob and container soft delete retain data for 30 days. Versioning and a 30-day change feed support recovery, and point-in-time restore is enabled for seven days.
- **Resilience and cost:** ZRS is the default. `account_replication_type` can be changed deliberately where another recovery/cost profile is required. No lifecycle rule deletes current application data.
- **Encryption:** Microsoft-managed service and infrastructure encryption are enabled. Cross-tenant replication is disabled, and copy operations are restricted to the same Entra ID tenant.
- **Network:** the public endpoint is enabled by default so AKS and App Service can use storage without additional network construction. It is not anonymous and still requires Entra ID authorization. Set `allowed_ip_addresses` and/or `allowed_subnet_ids` to opt into deny-by-default network rules; all other public sources are then denied. Subnets must already have the `Microsoft.Storage` service endpoint. Network restrictions and identity authorization are complementary.
- **Tags:** `application`, `component`, and `managed_by` are always applied. Additional `tags` can include environment, cost center, and ownership metadata.

## Identity running OpenTofu

The resource group and application identity must already exist. The identity running OpenTofu needs permission to create storage accounts and role assignments in that resource group. Because account keys are disabled, container provisioning uses Entra ID (`storage_use_azuread = true`); the OpenTofu identity also needs **Storage Blob Data Contributor** (or Owner) at a scope inherited by the new account. This requirement applies to the deployment identity, not the application identity.

## Outputs

The module exposes the account ID/name, primary blob endpoint, container IDs/names/URLs, and the application role assignment ID. It intentionally exposes no keys, SAS tokens, or connection strings.
