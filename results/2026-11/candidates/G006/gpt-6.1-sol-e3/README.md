# Application Blob Storage

A standalone OpenTofu root for an application's uploads, media, reports and exports. It creates storage **inside an existing application resource group**, in that group's Azure region. It does not create the group, application identity, AKS cluster or App Service. Use a separate deployment/state for each application/environment.

## Quick start

Copy this directory, edit `minimal.tfvars`, and replace all three example values:

```hcl
resource_group_name      = "orders-staging"
storage_account_name     = "ordersstagingapp7d93"
application_principal_id = "11111111-2222-4333-8444-555555555555"
```

The account name must be globally unique across Azure, 3–24 lowercase letters/digits. The principal ID is the **object ID** of the existing application service principal or managed identity, not its client ID, tenant ID or Azure resource ID. The UUID above is a placeholder; supply a real identity before applying.

Authenticate the AzureRM provider using your normal environment credentials (including `ARM_SUBSCRIPTION_ID`; CI can use workload identity/OIDC). Then:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The deployment identity must be allowed to create/manage storage resources in the existing group and create role assignments (for example, Contributor plus Role Based Access Control Administrator). AzureRM's Blob service operations also need Blob data-plane permissions, such as Storage Blob Data Contributor inherited from the resource group. These are deployment permissions, not permissions granted to the application by this root. Role assignments can take several minutes to propagate.

For team use, configure a secured remote state backend with locking before applying. No backend is hardcoded here. Treat state as sensitive: providers may retain computed account credentials even though Shared Key authentication is disabled and this module does not output keys.

## Defaults and decisions

- **Blob Storage**, not Azure Files: object storage is appropriate for these files and works from both AKS and App Service through the Azure SDK. No filesystem mount, hierarchical namespace or static website is provisioned.
- Standard StorageV2, Hot tier, **ZRS** for availability across zones. Azure manages encryption at rest. ZRS is not regional disaster recovery; choose geo-redundancy explicitly if needed. The selected region must support the replication type.
- One private container, `app-data`. The application receives **Storage Blob Data Contributor scoped to each managed container**, not the subscription, group or entire account. It can read, write and delete blobs; it receives no account-management role. No existing identities are created or modified.
- Entra token authentication, HTTPS only, TLS 1.2 minimum. Shared Key authorization and anonymous/public blob access are disabled. No account keys or connection strings are exported.
- The service's **public network endpoint remains reachable** so existing AKS/App Service deployments work without assuming VNet integration or private DNS. This is identity-protected storage, **not private-endpoint-only storage**. No private endpoints, firewall allowlists, CORS rules or network infrastructure are provisioned. If organizational policy requires private networking, extend the design with the application's actual subnet and DNS topology before deployment; do not simply disable the endpoint and leave applications disconnected.
- Blob versioning and 30-day blob/container soft delete protect against common accidents. Old versions and snapshots become eligible for deletion after 90 days; current blobs are never lifecycle-expired. Soft delete can extend actual retention beyond the lifecycle threshold. Recovery/versioning costs additional storage and does not constitute an independent backup or compliance retention guarantee.
- No automatic expiration or tiering of live application data. Tags are supplied by the caller. Monitoring destinations, budgets, malware scanning and backup policies are organization-specific and are not created here.

## Application configuration

Use the `blob_endpoint` output and a container name from the `containers` output with an Azure SDK token credential (for example, `DefaultAzureCredential`). App Service must have the specified managed identity attached and select it if user-assigned. AKS must already have workload identity federation/service-account configuration for the specified identity. This root grants storage access only; it does not configure application hosting or identity federation. No SAS or storage connection string is needed. Avoid putting application identity credentials into tfvars.

## Optional configuration

```hcl
containers       = ["uploads", "reports"]
replication_type = "ZRS"
tags = {
  application = "orders"
  environment = "production"
  owner       = "orders-team"
}
```

`containers` defaults to `["app-data"]`; all names must follow Azure container naming rules. Every listed container gets the same application access. `replication_type` defaults to `ZRS`; `LRS` is a cheaper option for disposable environments or regions without ZRS. `GRS`, `GZRS`, `RAGRS` and `RAGZRS` are also accepted, subject to Azure region/account support. `tags` defaults to `{}`.

Outputs: `storage_account_id`, `storage_account_name`, `blob_endpoint`, and `containers` (name-to-resource-ID map).

## Change and deletion safety

Review plans carefully: changing account name or resource group can replace the account; removing/renaming a container schedules its deletion. Destroying the root deletes the account and its data. Blob/container soft delete is not protection against account deletion. Keep backups where required and use organizational locks/approval controls for production. Removing an application's managed role assignments does not revoke permissions granted separately outside this root.
