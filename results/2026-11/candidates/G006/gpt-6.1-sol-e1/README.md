# Application blob storage

A standalone OpenTofu root for application uploads, media, reports and exports in Azure public cloud. Creates **Blob Storage**, not an SMB/NFS filesystem, Azure Files share, or static website. Each deployment belongs to one application in one environment. Use a separate root state and account for staging and production.

## Quick start

The application's resource group and Entra service principal/managed identity must already exist. Copy `minimal.tfvars` to an environment-specific file and replace its three example values:

```hcl
resource_group_name      = "orders-prod"
storage_account_name     = "ordersprodfiles87421" # globally unique, lowercase, 3–24 characters
application_principal_id = "11111111-2222-4333-8444-555555555555" # object ID, NOT client ID
```

Authenticate the AzureRM provider using your normal environment-based credentials, including `ARM_SUBSCRIPTION_ID`. Then:

```sh
tofu init
tofu plan -var-file=prod.tfvars
tofu apply -var-file=prod.tfvars
```

The example identity UUID is a placeholder; a plan cannot establish that it exists. Replace it before applying. The deployment identity needs storage/network resource creation permissions in the existing resource group and `Microsoft.Authorization/roleAssignments/write` at the container scope (e.g. Contributor plus Role Based Access Control Administrator at the resource group). Private endpoint deployments additionally need subnet join and private DNS zone permissions. The module does not create identities, resource groups, role grants for its deployer, or federated credentials.

## Defaults and guarantees

- Uses the existing resource group's location and tags; `tags` can add/override tags.
- Standard StorageV2, Hot access, ZRS. ZRS tolerates a zone outage but is **not** a regional disaster recovery strategy or a backup. Check region support; `replication_type = "LRS"` is available for unsupported regions or less critical workloads. Geo-redundancy choices are also supported, with added cost and asynchronous replication.
- One private `files` container. Override `containers = ["uploads", "exports"]` if the app needs separation. No anonymous blob access, account keys, account-key SAS, or connection-string credentials for the application.
- The existing application identity receives **Storage Blob Data Contributor on each managed container only**, not Owner/Contributor on the account or resource group. It can read/write/delete blobs in those containers. The Azure built-in data role also includes container actions within that scope. No account-wide data role is granted. Existing external role assignments are not revoked.
- HTTPS only, TLS 1.2 minimum, Azure encryption at rest plus infrastructure encryption. Microsoft-managed keys avoid introducing a key-vault operational dependency. Cross-tenant object replication is disabled.
- Blob versioning and 30-day blob/container soft delete. A lifecycle policy expires old block-blob versions and snapshots after `recovery_days` (default 30); it never expires current blobs. Soft deletion can retain expired versions longer, and lifecycle processing is asynchronous. This is recovery from routine mistakes, not immutable backup/ransomware protection. Budget for retained versions and large overwrite workloads.
- Account destruction/replacement is blocked by `prevent_destroy`. To intentionally decommission, export/confirm deletion of data and deliberately change that guard in code. Removing the entire resource block bypasses this protection. Container removal/rename is destructive and not blocked: migrate data before changing names; container soft delete is only a time-limited recovery option.

## Application integration

Pass the `blob_endpoint` output and a container name to the Azure Blob SDK. Use Azure Identity's `DefaultAzureCredential` (or an explicitly selected managed/workload identity), not an access key. `containers` output contains ARM IDs and URLs; no credentials are output.

For AKS, the platform team must configure AKS Workload Identity/OIDC federation to the existing application identity and annotate the workload's service account. For App Service, attach/enable that identity on the application; user-assigned identities may require selecting the client ID in SDK configuration. Those compute-side changes are deliberately outside this storage root. Allow several minutes for Azure RBAC propagation; SDK retries may be needed after provisioning. For local development, use an Entra identity explicitly granted a suitable data role through your normal access process.

## Networking: usable default, private option

By default the HTTPS service endpoint is network-reachable publicly, but **all data still requires Entra authorization**. This deliberate default works with existing AKS and App Service deployments without guessing subnets, outbound IPs or DNS. A private container is an authorization setting, not a private network endpoint. For applications requiring network isolation, set:

```hcl
private_endpoint = {
  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/apps/subnets/endpoints"
  private_dns_zone_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}
```

This creates a blob private endpoint and DNS zone group, and disables public data-plane access. The platform team must supply a suitable existing subnet, zone linked to client VNets, routing/peering, and working DNS forwarding. App Service needs VNet integration; AKS needs connectivity to that subnet. This root does not modify shared VNets or DNS links. SDKs continue using the normal `blob_endpoint` hostname, resolving privately. Deploy/manage from a connected runner where provider data-plane operations require connectivity.

## Operations and limits

Optional inputs and validation are documented in `variables.tf`; only the three quick-start inputs are required. The module does not configure browser CORS, hierarchical namespaces, SFTP, public hosting, queues, tables or file shares. Browser uploads should use an application-controlled, short-lived user-delegation SAS flow, not enable public access; account-level delegation-key permissions and CORS would need a separately reviewed design.

No monitoring destination is assumed: enable your organization's subscription policy/diagnostic collection for blob request logs, alerts and cost monitoring. Blob contents and restore workflows are managed by applications/operators, not OpenTofu. Test restores periodically. Account names must be globally available; changing name/location may require replacement, which the destruction guard blocks. Protect remote state with encryption and access controls: AzureRM may persist account key attributes in state even though key-based requests are disabled. No remote modules are used.
