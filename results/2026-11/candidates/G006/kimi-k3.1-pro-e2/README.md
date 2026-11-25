# Standard application storage

Creates one general-purpose Azure Storage account in an application's existing resource group, private blob containers, and data-plane access for the application's existing Entra ID identity.

## App-team usage

Copy `examples/basic/main.tf` and provide:

- `application_name`: a short name such as `orders`.
- `resource_group_name`: the existing application resource group, such as `orders-staging`.
- `application_principal_id`: the **object ID** of the application's managed identity or workload-identity service principal (not its client ID).

`containers` defaults to `["uploads"]`. Override it with names such as `uploads`, `media`, `reports`, and `exports` when the application needs separate containers. `tags` and `replication_type` are optional; everything else has a module-owned default.

The account name is generated automatically. Its stable suffix is derived from the subscription-scoped resource group ID, avoiding a global-name input or random resources that change on every run.

## What the module standardizes

- General-purpose StorageV2, Standard tier, Hot access tier, and LRS redundancy by default.
- HTTPS only, TLS 1.2 or later, encryption at rest, and infrastructure encryption.
- Entra ID authentication for applications; shared keys and anonymous blob access are disabled.
- Private containers and **Storage Blob Data Contributor** for the supplied application principal at account scope.
- Blob and container soft delete (14 days), blob versioning, change feed, and seven-day point-in-time restore.
- Automatic expiry of noncurrent blob versions and snapshots after 30 days. Active blobs are never automatically deleted, archived, or moved to a cooler access tier.
- No hierarchical namespace, NFS, SFTP, local users, or cross-tenant replication.
- Resource-group location and tags, plus standard application and management tags.
- A public HTTPS endpoint with Azure AD authorization, suitable for AKS and App Service without requiring network configuration. This is not an anonymous/public-data account.

Containers are managed through Azure's control plane so applying the module does not depend on storage account keys or data-plane access for the deployment identity.

## Application configuration

Use `primary_blob_endpoint` and `container_names` as application configuration. Applications should authenticate with their existing identity (for example, `DefaultAzureCredential` in an Azure SDK) and request blobs in one of the created containers. No access keys or connection strings are outputs.

The role assignment grants data access; it does not grant permission to manage the storage account. Role propagation can take a few minutes after the first apply.

## Root-module smoke test

The included `minimal.tfvars` supplies every required input. With Azure credentials and the referenced existing resource group available:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

## Outputs

- `storage_account_id` and `storage_account_name`
- `primary_blob_endpoint`
- `container_names` and `container_ids`
- `application_principal_id`
