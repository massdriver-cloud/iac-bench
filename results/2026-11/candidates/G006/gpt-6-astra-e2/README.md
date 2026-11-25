# Application file storage

Standalone OpenTofu root configuration for **Azure Blob Storage**: uploads, images,
videos, reports and exports accessed through an SDK/HTTPS. This is not an Azure
Files/SMB share or a Kubernetes persistent volume. It creates no resource group,
application identity, AKS cluster or App Service, and uses no remote modules.
Deploy one account and one independent state per application/environment.

## Quick start

1. Copy `minimal.tfvars` to `app.tfvars` and replace its three example values:

   ```hcl
   resource_group_name      = "orders-staging"
   storage_account_name     = "ordersstg7f3a91c2"
   application_principal_id = "b6d871a3-6b98-4ae0-9acb-28ea55fc4812"
   ```

   The resource group and identity must already exist in your subscription/tenant.
   The account name must be globally unique. The identity input is the **object /
   principal ID**, not the client ID. Use a different application identity per
   environment to maintain isolation. Location and tags come from the group.

2. Authenticate the deployment through the environment (for example `ARM_SUBSCRIPTION_ID`,
   `ARM_TENANT_ID`, `ARM_CLIENT_ID` and your organization's service-principal or
   OIDC authentication settings), or Azure CLI with `ARM_SUBSCRIPTION_ID` set.
   The deployer needs resource-group read access, storage management permissions,
   and `Microsoft.Authorization/roleAssignments/write` and `/delete` on the target
   scopes (for example Contributor plus Role Based Access Control Administrator).
   The subscription must have Microsoft.Storage registered, or the deployment
   identity must be allowed to register providers. The application itself does
   **not** need these deployment privileges.

3. Run:

   ```sh
   tofu init
   tofu fmt -check
   tofu validate
   tofu plan -var-file=app.tfvars -out=app.tfplan
   tofu apply app.tfplan
   tofu output
   ```

   Use OpenTofu >= 1.6. Configure a protected remote state backend before shared
   or production use. No backend is hard-coded because each team/environment
   needs an independent state. Commit the provider lock file. Protect state and
   saved plans: the provider can store account keys even though key authentication
   is disabled and this module does not output them.

## Connecting the application

Use `blob_endpoint` and the default container name `files` (or `container_urls`).
Use an Azure Blob SDK with `DefaultAzureCredential` rather than a connection string.
For example, Python with `azure-identity` and `azure-storage-blob`:

```python
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

service = BlobServiceClient(
    account_url=os.environ["BLOB_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
service.get_blob_client(container="files", blob="reports/example.txt").upload_blob(
    b"example report", overwrite=True,
)
```

For AKS, configure Workload Identity, its federated credential and the pod's
service account for the existing identity outside this module. For App Service,
attach/enable the existing managed identity; for a user-assigned identity configure
its client ID in the SDK (e.g. `AZURE_CLIENT_ID`). These runtime identity steps are
not accomplished by the storage role assignment. Allow several minutes for new
RBAC assignments to propagate; retry transient authorization failures.

The identity receives **Storage Blob Data Contributor on each configured container**,
not Contributor/Owner on the account or group. It can read, write and delete blob
data; other containers receive no grant from this module. Existing broader role
assignments are not revoked. Humans do not automatically receive data access.
There are no passwords, account-key connections, anonymous blob URLs or account-key
SAS tokens. Serve private downloads through the app. Browser-direct uploads,
user-delegation SAS (requiring an additional account-level delegation permission),
CORS, CDN and public static hosting are deliberately outside this baseline.

## Defaults and trade-offs

- Standard StorageV2, Hot tier, **ZRS** for availability-zone resilience. This is a
  general-purpose choice for actively used application files. Azure encrypts data
  at rest with Microsoft-managed keys; no Key Vault/CMK dependency is introduced.
- HTTPS only, TLS >= 1.2; anonymous container access and shared-key authentication
  are disabled. SFTP, hierarchical namespace and local users are disabled.
- **The HTTPS endpoint is publicly reachable, but data is private and requires
  Entra authorization.** This works with both AKS and App Service without assuming
  a VNet or DNS configuration. A private container does not mean a private endpoint.
- `network_access` optionally restricts the public endpoint to `ip_rules` and/or
  `subnet_ids`. Subnets must already have Microsoft.Storage service endpoints;
  App Service must have suitable VNet integration or stable permitted outbound
  addresses. Azure has restrictions on same-region IP filtering: prefer service
  endpoints for Azure workloads. No trusted-service firewall bypass is enabled.
  Container creation uses ARM, not the restricted Blob endpoint. This module does
  not provision Private Link or private DNS; environments mandating those require
  a separate reviewed networking design rather than this public-endpoint baseline.
- Blob versioning plus 30-day blob and container soft deletion aid recovery.
  Previous block-blob versions and snapshots become eligible for cleanup after
  **30 days from creation**, not 30 days from becoming noncurrent. Cleanup is
  asynchronous; soft-delete retention can add storage charges. Current blobs are
  never automatically expired or tiered. These controls are not immutable backup,
  point-in-time restore or protection from deletion of the whole storage account.
  Restore deleted containers/blobs or copy a retained version with Azure's recovery
  tools using an appropriately authorized operator identity.
- `prevent_destroy` blocks planned account deletion/replacement while the resource
  declaration remains present. Renaming/moving the account or immutable setting
  changes may therefore fail rather than lose data. Migrate data first; intentional
  retirement requires a reviewed edit to that lifecycle guard. It is not an Azure
  resource lock and cannot stop portal deletion or removal of the resource block.
  Removing a container from `containers` still deletes that container: review plans.

## Optional inputs

| Input | Default | Use |
| --- | --- | --- |
| `containers` | `["files"]` | Private container names; every one gets the same app access |
| `replication_type` | `"ZRS"` | LRS for lower-cost dev or regions without ZRS; GRS/RAGRS/GZRS/RAGZRS for explicit regional DR choices |
| `tags` | `{}` | Merge with/override resource group tags |
| `network_access` | `null` | Optional firewall allowlist; not Private Link |

Example additions to `app.tfvars`:

```hcl
containers       = ["uploads", "exports"]
tags             = { owner = "orders-team", cost_center = "commerce" }
# Only if these are your actual stable public egress addresses:
network_access   = { ip_rules = ["203.0.113.10"] }
```

ZRS availability and globally unique naming are Azure constraints. Choose an
appropriate region/resource group before deployment. Cross-region replication is
asynchronous, costs more and requires an operational failover plan; ZRS alone does
not survive an entire-region loss. Recovery versions and soft-deleted data also
consume billed capacity. This module intentionally does not delete live uploads or
exports to save money. Provision monitoring, budgets and any independent backup
according to the application's operational requirements.

Outputs: `storage_account_id`, `storage_account_name`, `blob_endpoint`,
`container_urls`. No secret outputs are defined.
