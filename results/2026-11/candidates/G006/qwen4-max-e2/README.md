# Standard application storage account (Azure Blob Storage)

The standard way for an application team to get storage for its files
(uploads, images/videos, reports/exports). You supply two obvious inputs;
the module makes every other decision for you.

## Usage

```hcl
# Copy this, change two lines, done.
resource_group_name = "orders-staging" # your app's existing RG for this environment
name                = "orders"        # short app name
```

Then, for your app's identity (recommended — see below):

```hcl
principal_ids = ["00000000-0000-0000-0000-000000000000"] # your app's managed identity object ID
```

Run `tofu apply -var-file=example.tfvars`.

## What you get

- A **StorageV2 / Standard / Hot** blob storage account in your app's
  **existing resource group**, in the **same region** as the group.
- **Zone-redundant (ZRS)** by default — survives a datacenter outage.
- A globally unique account name derived from your app name (Azure's
  3–24 lowercase-alphanumeric rule is handled for you).
- A private `data` blob container (add more with `containers = [...]`).
- **Accidental-deletion protection**: blob versioning plus 14-day soft
  delete for blobs and containers.

## How your app authenticates

Access keys are **disabled**. Your app uses its existing Entra ID
managed identity (AKS workload identity or App Service identity):

1. Find the identity's **object (principal) ID** (not the client ID).
2. Pass it in `principal_ids`. The module grants it
   **Storage Blob Data Contributor** on the account.
3. In code, use any Azure SDK with `DefaultAzureCredential` /
   `ManagedIdentityCredential` and the `primary_blob_endpoint` output.

No connection strings, keys or SAS tokens to store or rotate.

## Network access

The firewall defaults to **Deny** with trusted Azure services bypassed.
If your app talks to storage from an AKS or VNet-integrated App Service
subnet, enable the `Microsoft.Storage` service endpoint on that subnet
and pass its resource ID:

```hcl
virtual_network_subnet_ids = ["/subscriptions/.../subnets/aks"]
```

For occasional debugging from a fixed public IP, use `allowed_ip_ranges`.

## Security posture (not configurable — this is the standard)

- HTTPS only, TLS 1.2 minimum.
- No anonymous/public blob access; all containers are private.
- Shared access keys disabled; Entra ID authentication only.
- No SFTP/NFS/local users.

## Optional knobs

| Variable | Default | Purpose |
|---|---|---|
| `containers` | `["data"]` | Private containers to create |
| `principal_ids` | `[]` | App identity object IDs to grant blob data access |
| `replication_type` | `"ZRS"` | Redundancy (`LRS` for cheap scratch data) |
| `virtual_network_subnet_ids` | `[]` | App subnets allowed through the firewall |
| `allowed_ip_ranges` | `[]` | Extra public IPs/CIDRs allowed |
| `tags` | `{}` | Extra tags (module adds `managed-by`, `workload`) |

## Outputs

`storage_account_id`, `storage_account_name`, `primary_blob_endpoint`,
`container_names`, `container_ids`, `resource_group_name`, `location`.
