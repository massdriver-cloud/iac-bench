# Application file storage

Standalone OpenTofu root for an application's **Azure Blob Storage**, not an SMB filesystem or an AKS persistent volume. Uploads, images, videos, reports and exports are stored as blobs via the Azure SDK. It uses the application's existing resource group and existing Entra service principal/managed identity; it does not create either, change the resource group, or configure AKS/App Service identities.

## Quick start

Requires OpenTofu >= 1.6, AzureRM 4.x, and Azure credentials (for example workload identity environment variables including `ARM_SUBSCRIPTION_ID`).

Copy `minimal.tfvars` to an environment-specific file and replace the three example values:

```hcl
resource_group_name      = "orders-prod"
storage_account_name     = "ordersprodfiles123" # globally unique, lowercase/digits, 3-24 chars
application_principal_id = "11111111-2222-4333-8444-555555555555" # replace with real principal/object ID

# Optional:
# containers = ["uploads", "exports"]
# tags       = { application = "orders", environment = "prod" }
```

The example UUID is a placeholder, not a created identity. Supply the **object/principal ID**, not the application's client ID. The group must already exist in the selected subscription. The account is created in the group's region, which must support Standard ZRS. Use a separate state and variable file for each app/environment.

```sh
tofu init
tofu plan -var-file=prod.tfvars
tofu apply -var-file=prod.tfvars
tofu output
```

The deployment identity needs storage resource management permissions and `Microsoft.Authorization/roleAssignments/write` at the resource group (e.g. Contributor plus Role Based Access Control Administrator). AzureRM can also access storage service settings through data-plane APIs; give the deployment identity Storage Blob Data Owner at resource-group scope before deployment when using Entra authentication. It is deliberately separate from the application's narrowly scoped role. Allow time for role propagation.

## Defaults and rationale

- Standard StorageV2, Hot tier: general-purpose, frequently accessed application objects without premium pricing.
- ZRS: synchronous redundancy across availability zones. No cross-region disaster recovery is implied; use a supported region. Encryption at rest uses Azure-managed keys with infrastructure encryption enabled.
- HTTPS only, minimum TLS 1.2. Anonymous blob access, shared-key authentication, cross-tenant replication and SFTP/local users are disabled. No secrets or connection strings are exposed as outputs.
- One private `files` container by default. Optional `containers` replaces that set.
- The app receives **Storage Blob Data Contributor on each managed container**, not account management privileges, access to other accounts, or access to future unmanaged containers. This permits listing, reading, writing and deleting application blobs. Existing role assignments outside this root are not removed.
- Blob versioning and 30-day blob/container soft deletion protect against accidental edits and deletes. A lifecycle policy deletes previous block-blob versions after 90 days; it never expires current blobs. Soft deletion can retain deleted versions for an additional 30 days. Retained data costs money. This is not an independent backup or protection against account deletion.
- Resource-group tags are inherited with explicit `tags` taking precedence.

**Network decision:** the HTTPS endpoint is publicly routable so both AKS and App Service work without new VNets, DNS zones or integration requirements. Public routing is not anonymous access: requests require Entra authorization. This root does not offer private endpoints, firewall restrictions, CORS, CDN access, public website hosting, queues, tables or file shares. If network isolation is mandatory, extend the design with approved private networking before using it; do not simply disable public access without a working client network path.

## Connecting applications

Use `blob_endpoint` and a `container_urls` entry from outputs with an Azure Blob SDK and `DefaultAzureCredential`; no storage key is needed. For example, Python:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

service = BlobServiceClient(account_url=blob_endpoint,
                            credential=DefaultAzureCredential())
files = service.get_container_client("files")
files.upload_blob("reports/example.txt", b"example", overwrite=True)
```

For AKS, enable Workload Identity and configure the service account, federated credential and client-ID annotation for the existing identity. For App Service, attach/enable the existing managed identity; select the user-assigned identity's client ID in the credential configuration when necessary. Those runtime integrations are outside this root. The role input is still the identity's **principal ID**, not that runtime client ID. RBAC changes can take several minutes to propagate. Browser direct uploads require a separately reviewed CORS and authorization design (such as short-lived user-delegation SAS), not account keys.

## Operations

Outputs: `storage_account_id`, `storage_account_name`, `blob_endpoint`, and `container_urls`. Container URLs are not SAS URLs and grant no access by themselves.

Review plans carefully: changing account name or resource group can replace the account; removing a container removes that container and its application grant. Destroying this root deletes storage and can permanently lose application data, including recovery history. There is no deletion lock; arrange independent backups and operational approval before destructive changes. Restore blobs/versions or deleted containers through Azure tooling within the retention window.

Configure an encrypted, access-controlled remote state backend in your deployment system; no backend is hard-coded here. Protect state even though keys are not exported: provider-maintained account attributes may contain sensitive material. Pin the generated provider lock file in your deployment repository. Set budgets and monitoring appropriate to the application's data volume; this root does not provision a shared logging workspace or external backup service.
