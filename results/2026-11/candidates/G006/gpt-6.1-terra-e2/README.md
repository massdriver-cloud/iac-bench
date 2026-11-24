# Application blob storage

This root configuration creates a StorageV2 account in an **existing** application resource group, a private `app` blob container, and an account-scoped Storage Blob Data Contributor role assignment for the application's existing Entra identity. It is intended for Azure Blob Storage SDKs, not a mounted filesystem or Azure Files share. The application can read, write, and delete blobs and manage containers in this account.

## Get started

1. Copy `minimal.tfvars` to a new, private `.tfvars` file and replace **all** example values:
   - `resource_group_name`: the existing application resource group in the target subscription.
   - `location`: its Azure region, for example `eastus`.
   - `storage_account_name`: a globally unique name of 3–24 lowercase letters and digits. Use a different name for each environment.
   - `application_principal_id`: the Entra **object/principal ID** of the application's service principal or managed identity in this tenant, not the application/client ID or Azure resource ID. For AKS workload identity or an App Service managed identity, use the principal ID of the identity actually used by the application.
2. Authenticate the AzureRM provider through the environment, including the target subscription (for example `ARM_SUBSCRIPTION_ID` and the appropriate Azure credential environment variables). The deployment identity needs permission to create and manage storage accounts and containers in the resource group and create/delete role assignments at the storage account scope. The resource group and application identity must already exist.
3. Run `tofu init`, `tofu plan -var-file=your.tfvars`, then `tofu apply -var-file=your.tfvars`. The checked-in `minimal.tfvars` is a planning example, not a deployable environment: its identity and resource group are placeholders and its account name may already be taken.
4. Configure the app with the `blob_endpoint` and `container_name` outputs. Use an Azure SDK's Entra credential chain (for example `DefaultAzureCredential`), configured for the app's managed/workload identity. Role assignments can take time to propagate; retry transient authorization failures. No account key or connection string is needed.

## Defaults and operational considerations

- Standard, Hot, locally redundant (LRS) storage is the default. LRS does **not** protect against loss of the region or provide zone redundancy. Set `replication_type` to `ZRS`, `GRS`, or `GZRS` where available and appropriate for the application's availability and disaster recovery requirements. Replication changes have Azure-specific constraints and costs.
- HTTPS and TLS 1.2 or newer are required; anonymous blob access and shared-key authorization are disabled. Access is via Entra RBAC. The account has a **public network endpoint**, with no IP firewall or private endpoint configured, so AKS and App Service need outbound connectivity to Azure Storage. RBAC protects the data, but this does not satisfy a private-network-only requirement; that needs additional network, DNS, and application integration design.
- Blob versioning and 30-day blob and container soft delete help recover accidental changes/deletions. Versions are retained until explicitly removed and incur storage costs. These protections are not an independent backup and do not protect against deletion of the storage account or resource group. `tofu destroy` deletes the account and its contents. Establish backup, retention, and lifecycle policies separately if required.
- Azure encrypts data at rest with Microsoft-managed keys. Optional `tags` are applied to the account. The account-wide role is intentionally scoped to this one application's account, rather than the resource group or subscription.
- Protect the OpenTofu state and restrict access to it: the AzureRM provider may store sensitive account attributes in state even though shared-key authentication is disabled. Do not commit real tfvars or state containing sensitive environment information.
