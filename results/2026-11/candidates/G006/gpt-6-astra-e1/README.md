# Application blob storage

A standalone OpenTofu root for **one application in one environment**, deployed into its **existing resource group**. Use separate state and account names for staging and production. No resource groups, app identities, AKS clusters, or App Services are created or modified.

This is Azure **Blob Storage** for uploads, media, reports, and exports—not Azure Files/SMB, a mounted filesystem, or a database. Applications use the Azure Blob SDK over HTTPS.

## Quick start

Copy this root and edit `minimal.tfvars`:

```hcl
resource_group_name      = "orders-staging"
storage_account_name     = "ordersstgfiles7c29b4" # choose your own globally unique name
application_principal_id = "a3aaf546-7f3a-4b02-86c7-9bd1bbd80d91" # replace with your identity's object ID
```

These are example literals, not an identity or resource group created by this module. The identity must be an existing service principal or managed identity in the deployment tenant. Its **object/principal ID** differs from the client ID used by application SDKs.

Authenticate the AzureRM provider using the deployment environment (for example, ARM_* variables with workload identity federation). Set `ARM_SUBSCRIPTION_ID`. The deployment principal needs storage resource management permissions in the application resource group and `Microsoft.Authorization/roleAssignments/write` and delete permissions at the relevant scopes (for example Contributor plus Role Based Access Control Administrator). The application's identity does **not** need these deployment permissions. No Entra directory lookup permissions are needed.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
tofu output
```

The resource group's location is used automatically. Verify ZRS availability in that region; explicitly choose `replication_type = "LRS"` for unsupported regions or cheaper nonproduction storage. The global account name must be available at apply time.

## Standard decisions

| Area | Default and rationale |
| --- | --- |
| Storage | Standard StorageV2, Hot tier: general-purpose, frequently accessed application objects. |
| Availability | ZRS: synchronous replication across availability zones. Not regional disaster recovery; opt into GZRS if required and supported. |
| Authentication | Existing application identity, Entra tokens only for blob access. Shared-key authorization and anonymous blob/container access are disabled. No connection strings or secrets are output. |
| Authorization | Storage Blob Data Contributor on each managed container, not the resource group or subscription. The app can read/write/delete its objects and manage its containers, but receives no account-management rights or access to other containers. |
| Transport/encryption | HTTPS only, TLS >= 1.2, Azure-managed encryption at rest plus infrastructure encryption. No customer-managed key lifecycle to operate. |
| Recovery | Blob versioning plus 30-day blob and container soft deletion. Previous versions and snapshots expire after 90 days from creation. Current blobs are never automatically expired or tiered. |
| Network | Public HTTPS service endpoint by default, **not public data**: every data request still needs authorization. This works with existing AKS/App Service without assuming their network topology. Private-only access is an explicit option below. |
| Tags | Inherit resource-group tags; caller tags override matching keys. |
| Deletion | `prevent_destroy` blocks planned account deletion/replacement while the resource remains in configuration. |

A private `files` container is created by default. Optionally set:

```hcl
containers       = ["uploads", "reports"]
replication_type = "ZRS" # LRS, ZRS, or GZRS
tags             = { owner = "orders-team", environment = "staging" }
```

There is deliberately no default expiration of reports/uploads, public website hosting, CORS policy, CDN, file share, queues, SFTP, or data-lake namespace. The module does not guess your data retention compliance requirements or introduce unrelated services.

## Connect the application

Use the `blob_endpoint` output as the SDK account URL and `files` (or a configured container name) as the container. Use a current Azure Identity SDK's `DefaultAzureCredential` with the Blob SDK. Do not configure account keys or connection strings.

* **AKS:** the platform must already enable OIDC/workload identity and federate the application's Kubernetes service account with the supplied Entra identity. Use the workload-identity pod label and service-account client-ID annotation. Passing a principal ID here does not configure federation.
* **App Service:** enable/attach the supplied managed identity to the application. For a user-assigned identity, select its **client ID** in the SDK configuration (`AZURE_CLIENT_ID` where supported). A system-assigned identity's principal ID is also supported.
* RBAC can take several minutes to propagate. Retry initial authorization failures with backoff. This module does not grant human developers data access; portal browsing also needs an appropriate data role.
* Serve user downloads through the authenticated application. Account/container anonymity is never enabled. Container-scoped permissions intentionally do not grant account-level user-delegation-key generation; direct-browser user-delegation SAS issuance would require a separately reviewed account-level delegator permission and any necessary CORS policy.

## Optional private-only access

If the platform has already provided private networking, add:

```hcl
private_endpoint = {
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/apps/subnets/private-endpoints"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}
```

This creates a blob private endpoint and DNS zone group, and disables public data-plane access with a deny-default firewall and no trusted-service bypass. It does not create or modify VNets, subnet delegation, VNet DNS links, or application routing. The subnet must support private endpoints in the resource group's region; the deployment identity needs subnet join and private DNS zone permissions. AKS/App Service must have network reachability (App Service VNet integration) and DNS resolution through the linked private zone. Use the same normal `blob_endpoint` URL; DNS resolves it privately. This option targets Azure public cloud's blob DNS zone.

Provisioning containers uses the ARM management API (`storage_account_id`), so it does not depend on shared keys or access to the blob data endpoint from the OpenTofu runner. The application still needs private connectivity for data access.

## Operations and boundaries

* Versioning, soft deletion, and replication incur storage charges; historical versions can be large for frequently rewritten objects. History cleanup is asynchronous and soft deletion may extend physical retention. No lifecycle rule deletes current data. Recovery is not an independent backup, and ZRS does not protect against regional failure. Define separate backup/compliance and regional recovery procedures when required.
* Renaming/removing a container is destructive. Container soft deletion provides a recovery window, not an automatic migration. Review every plan and test restoration procedures. Restoring an overwritten/deleted blob may require promoting a retained version.
* Changing an account name, resource group, region, or some encryption properties can require replacement, which `prevent_destroy` deliberately blocks. Migrate data first. Intentional retirement requires an explicit code review to remove that guard. It does not protect against portal deletion, resource-group deletion, or removal of the resource block from configuration; it is not an Azure resource lock.
* Use an access-controlled, encrypted, remote state backend for real environments. No backend is hard-coded. AzureRM may retain computed account keys in state even though shared-key blob authorization is disabled; treat state and saved plans as sensitive. Commit the provider lockfile, not state or credentials.
* Azure supplies platform metrics by default. Diagnostic log export, alerting, Defender plans, and log destinations are left to centralized platform policy rather than provisioning a new monitoring stack for each app. No diagnostic export or alerts are created here.
* Existing accounts are not automatically adopted. Import and review any migration separately; disabling shared keys can break legacy clients. Existing broader identity role assignments are not revoked by this module.

## Outputs

`storage_account_id`, `storage_account_name`, `blob_endpoint`, and `containers` (name to ARM ID/URL mapping). None is a credential.
