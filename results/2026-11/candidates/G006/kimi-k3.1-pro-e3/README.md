# Standard Azure application storage

An opinionated OpenTofu root module for an application's general-purpose files: uploads, images, videos, reports, and exports. It creates a dedicated StorageV2 account and private blob containers in the application's **existing** resource group, then grants the application's existing Entra ID identity blob read/write access.

## Quick start

Copy `minimal.tfvars` and replace its five values:

```hcl
application_name               = "orders"
environment                    = "staging"
resource_group_name            = "orders-staging"
location                       = "eastus"
application_identity_object_id = "12345678-1234-1234-1234-123456789012"
```

`application_identity_object_id` is the identity's **object/principal ID**, not its application/client ID. A user-assigned managed identity works for both AKS and App Service; a service principal can also be used.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The resource group and application identity must already exist. The deployment identity needs permission to create the storage resources and the role assignment in that resource group. The resource group itself is deliberately not managed by this module.

The account name is generated with a stable random suffix to satisfy Azure's global naming requirements. Use the `storage_account_name`, `primary_blob_endpoint`, and `container_names` outputs for application configuration.

## What the module decides for you

- General-purpose **StorageV2**, Standard tier, Hot access tier, and cost-conscious **LRS** redundancy. `replication_type` can be changed when recovery requirements justify ZRS or geo-redundancy.
- One private container named `data` by default. Set `container_names`, for example to `["uploads", "media", "reports"]`, when separate containers are useful.
- **Microsoft Entra ID only** for application data access. The application receives the least-privilege `Storage Blob Data Contributor` role at account scope. Storage shared-key authorization and anonymous/nested public blob access are disabled; no keys or connection strings are emitted.
- HTTPS only, TLS 1.2 or newer, Microsoft-managed encryption at rest plus infrastructure encryption, and no SFTP, NFS, or Data Lake surface.
- Blob soft delete, container soft delete, and blob versioning. Deleted data is retained for 30 days by default; noncurrent versions and snapshots expire after 30 days. The lifecycle policy never deletes the current version of a blob.
- Application, environment, and `managed-by` tags, with optional additional tags.
- A public Azure service endpoint by default for compatibility with AKS and App Service. Public network reachability does **not** permit anonymous data access. Optional firewall inputs can restrict it, or public network access can be disabled when private endpoints are managed by the platform/networking module.

Soft delete and versioning are recovery features, not a substitute for a backup or disaster-recovery design. Choose redundancy and any required backup separately according to the application's recovery objectives.

## Application configuration

Use the `primary_blob_endpoint` output with an Azure SDK's `DefaultAzureCredential` (or the language equivalent) and the identity whose object ID was supplied to the module. No storage access key is needed. For example, an application commonly needs only:

```text
AZURE_STORAGE_BLOB_ENDPOINT=<primary_blob_endpoint output>
AZURE_STORAGE_CONTAINER=data
# For a user-assigned managed identity, set its client ID:
AZURE_CLIENT_ID=<existing identity client ID>
```

## Optional customization

```hcl
container_names                 = ["uploads", "media", "reports"]
replication_type                = "ZRS"
soft_delete_retention_days      = 30
noncurrent_version_retention_days = 60

# Omit both firewall inputs for the default network-allow behavior.
# Supplying either input makes the firewall default action Deny.
allowed_ip_ranges  = ["203.0.113.10/32"]
allowed_subnet_ids = ["/subscriptions/.../subnets/aks"]

tags = {
  cost-center = "orders"
}
```

For private networking managed outside this module, set `public_network_access_enabled = false` and create the appropriate private endpoint and DNS records. Do not combine firewall allow lists with public network access disabled.

## Why AzAPI is used for containers

The storage account, RBAC assignment, and lifecycle policy use the AzureRM provider. Containers use an `azapi_resource` against Azure Resource Manager. This is intentional: unlike data-plane container creation with a storage key, ARM creation works while shared-key access is disabled and does not require the OpenTofu deployment identity to have blob data-plane permissions.
