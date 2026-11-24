# Application object storage

Standalone OpenTofu root configuration for **Azure Blob Storage**: uploads, media, reports and exports accessed through an SDK/HTTPS. It is not an SMB/NFS filesystem or an AKS persistent-volume module. One account per application/environment, inside its **existing** resource group; this configuration never creates or owns that group or the app's identity. No remote modules are used.

## Quick start

1. Copy this root configuration into the application's infrastructure directory. Use separate state for each application/environment (configure your team's secure remote backend before production use).
2. Copy/edit `minimal.tfvars`:

   ```hcl
   resource_group_name      = "orders-staging"
   storage_account_name     = "ordersstgfiles7b92e1"
   application_principal_id = "6bf51240-b6e3-4df2-90ec-eef172bd1764"
   ```

   These are example literals: select your existing group, a globally unique account name, and your **existing identity's object/principal ID**, not its client ID. For a managed identity use `principalId`; for an app registration use the enterprise application's service principal object ID in the deployment tenant. No new identity or secret is created.
3. Authenticate the AzureRM provider through the environment (for example your CI's federated Azure identity and `ARM_SUBSCRIPTION_ID`; locally Azure CLI login plus `ARM_SUBSCRIPTION_ID`). Do not put credentials in tfvars. The deployment identity needs resource-group read, storage management permissions, and role-assignment write/delete at this group, e.g. Contributor plus Role Based Access Control Administrator. The application's identity is separate from the deployment identity. Container provisioning uses ARM, not storage keys.
4. Run:

   ```sh
   tofu init
   tofu fmt -check
   tofu validate
   tofu plan -var-file=minimal.tfvars -out=storage.plan
   tofu apply storage.plan
   tofu output
   ```

A default deployment creates one account, one private `files` container, one container-scoped role assignment, and a recovery-history lifecycle policy. The resource group's location is used. The group and principal must already exist in the selected subscription/tenant; a plan cannot establish global name availability or whether an object ID belongs to the intended app.

## Application integration

Use `blob_endpoint` and a container from the `containers` output with your Azure SDK. There are deliberately **no keys or connection-string outputs**.

```python
# pip install azure-identity azure-storage-blob
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

service = BlobServiceClient(
    account_url=os.environ["APP_STORAGE_BLOB_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
container = service.get_container_client("files")
container.upload_blob("reports/example.txt", b"hello", overwrite=True)
```

Set `APP_STORAGE_BLOB_ENDPOINT` from the output. On AKS, use your existing workload identity federation/service account setup. On App Service, enable/attach the existing managed identity (for a user-assigned identity, select its client ID in the SDK, e.g. `AZURE_CLIENT_ID`). This configuration grants access; it does not wire the identity into the workload. The SDK requests tokens for Azure Storage. Role assignments can take several minutes to propagate; use bounded retry/backoff for initial authorization failures.

The app gets **Storage Blob Data Contributor only on the configured containers**, not the account or resource group. This permits reading, writing and deleting blob data and container operations allowed by that built-in role. It cannot manage the account or list all account containers. Use the known container names. Generating user-delegation SAS requires an additional account-scoped permission that is intentionally not granted. End-user browsers cannot access blobs anonymously; proxy access through the authenticated application unless you deliberately design a separate delegated-access flow. No permissive CORS policy is installed.

## Defaults and tradeoffs

| Choice | Reason |
| --- | --- |
| Standard StorageV2, Hot tier | General-purpose, actively used application objects; no premium performance assumptions. |
| ZRS | Survives an availability-zone failure without geo-failover operations. Not protection against a whole-region outage. Choose a supported region; this module does not silently downgrade redundancy. |
| Entra ID only | Shared-key/account-SAS authorization, anonymous blob access and local users are disabled. TLS 1.2 minimum and HTTPS only. |
| Platform-managed encryption plus infrastructure encryption | Encryption at rest without requiring teams to operate a Key Vault or rotate keys. |
| Public endpoint, authenticated | Works from existing AKS and App Service without requiring network changes. **Public reachability is not anonymous access.** This is not private-network-only storage. |
| Versions and 30-day blob/container soft deletion | Recovery from common overwrite/delete mistakes. Recovery is an operator action, not an automatic rollback. |
| History cleanup after 90 days | Removes old block-blob versions and snapshots by their creation age, never current blobs. Processing is asynchronous; soft deletion may extend billed retention. This is not a guaranteed 90-day window since an overwrite. |
| Account `prevent_destroy` | Blocks OpenTofu account destruction/replacement while the lifecycle rule remains configured. Renaming/moving/replacing an account needs an explicit data-migration decision. |

Version history, snapshots and soft-deleted data incur storage costs. There is no automatic deletion or cold-tiering of current application data. Soft deletion/ZRS are **not backups**: account deletion and regional disasters require a separately designed backup/DR strategy. This module does not create monitoring destinations, alerts, private endpoints, DNS zones, or compliance immutability policies.

## Optional settings

```hcl
container_names  = ["uploads", "reports"] # defaults to ["files"]
replication_type = "ZRS"                  # default; LRS, GRS, RAGRS, GZRS, RAGZRS also accepted

tags = {
  application = "orders"
  environment = "staging"
  owner       = "orders-team"
}

# Omit this object for authenticated access from any network.
# Prepare the subnet's Microsoft.Storage service endpoint beforehand.
network_restrictions = {
  subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network/providers/Microsoft.Network/virtualNetworks/apps/subnets/workloads"]
  ip_rules   = []
}
```

`managed_by = "OpenTofu"` is always included. Replication availability depends on the Azure region; LRS is a lower-resilience, lower-cost option for nonproduction or regions without ZRS. Replication changes may need Azure migration procedures.

When an allowlist is supplied, unmatched public traffic is denied and no trusted-service bypass is enabled. Use subnet rules for same-region Azure workloads (public IP rules do not reliably represent that traffic). App Service needs supported VNet integration; AKS needs the permitted workload egress/subnet path. Azure Storage only accepts supported public IPv4 IP rules, not private addresses; /31 and /32 CIDRs should be supplied as individual addresses where appropriate. Ensure support operators and any data-plane automation can reach the endpoint. A private-endpoint-only deployment requires a separately designed network/DNS extension rather than pretending an allowlist provides private connectivity.

## Operations

- Keep the generated provider lockfile. Protect remote state and plan artifacts: provider state can contain sensitive account attributes even though shared-key authorization is disabled and this module exposes no keys.
- Removing/renaming a container destroys the old container and its app grant. Review destructive plans carefully; soft-deleted containers can be restored within 30 days by an authorized operator, but the module does not perform restores.
- `prevent_destroy` is an OpenTofu guard, not an Azure resource lock: it does not stop portal deletion, resource-group deletion, or deletion after removing the resource configuration. To intentionally retire an account, first export/backup needed data and obtain approval, then deliberately remove that guard and review the destroy plan. Never use this as the only data-protection measure.
- Diagnostics/export and alerting should be connected to the organization's observability platform when available; no workspace or retention destination is assumed here.
