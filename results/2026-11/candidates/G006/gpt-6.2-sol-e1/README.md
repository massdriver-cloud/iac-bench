# Application blob storage

Deploy this OpenTofu root module once per application environment. It creates a StorageV2 account and a Blob private endpoint in the application's existing resource group. Use it for uploads, media, reports, and exports accessed through the Azure Blob SDK or REST API. It does not provide a mounted file share or a public asset endpoint.

## Get started

1. Copy `minimal.tfvars` to `orders-staging.tfvars` (or your environment's name). Replace the example values with your application's resource group name, its Entra **principal/object ID** (not its client ID), and the private endpoint subnet and Blob private DNS zone IDs supplied by your platform team. Keep separate state for each environment.
2. Use your team's protected state backend and AzureRM environment authentication, including `ARM_SUBSCRIPTION_ID` for the subscription containing the application resource group. Run:

   ```sh
   tofu init
   tofu plan -var-file=orders-staging.tfvars
   tofu apply -var-file=orders-staging.tfvars
   tofu output -json container_urls
   ```

3. Point your application's Blob SDK client at `blob_endpoint` and use the `app-data` container (or use its URL from `container_urls`). Authenticate using the app's existing identity: use AKS Workload Identity on AKS or the configured managed identity on App Service. Use the SDK's Entra credential flow (for example, `DefaultAzureCredential`); do not configure a storage key or account connection string. Allow time for the Azure role assignment to propagate before testing reads and writes.

### Platform prerequisites

- The existing application resource group must be in a region that supports Standard ZRS. The storage account uses that region. The endpoint defaults to the same region; set `private_endpoint_location` if the endpoint subnet's VNet is elsewhere.
- The app needs routing to the endpoint subnet and DNS resolution through the existing `privatelink.blob.core.windows.net` zone. For example, use AKS networking with a route to the endpoint, or App Service outbound VNet Integration, and link the zone to the appropriate VNet or provide resolution through a shared DNS resolver. This module manages the endpoint's DNS record through a zone group, not the zone, VNet links, or the runtime's network integration. From the running workload, verify that the normal account Blob hostname resolves to the endpoint's private IP.
- The deployment identity needs management-plane permissions for storage, containers, the private endpoint and its approval, and role assignment in the app resource group, plus join permissions on the subnet and DNS zone. Register `Microsoft.Storage` and `Microsoft.Network` in the relevant subscriptions ahead of time. Container provisioning uses Azure Resource Manager and does not require the deployment runner to reach the private Blob endpoint.

## Defaults and data protection

- Standard Hot Blob storage with zone redundancy and Azure-managed encryption at rest. ZRS protects against a zone failure, not a regional outage.
- Private containers, no public network access or anonymous blobs, no Shared Key authentication, and HTTPS with TLS 1.2 or later.
- The supplied application principal gets `Storage Blob Data Contributor` at each provisioned container, not at the account or resource group. Set `container_names` if the app needs more containers or a different name. Use `tags` for ownership or cost tags.
- Blob versioning plus 14-day soft delete for blobs and containers. Old versions can accrue storage charges; nothing automatically expires live data or previous versions. Soft delete and versioning are not backups for deletion of the storage account. Review destroy and replacement plans before applying them, especially when removing or renaming a container.
- Account names are derived from the full resource group ID, so re-planning does not generate a different name and staging and production get distinct names. The outputs expose endpoints and identifiers, not credentials. Restrict state access because provider-managed state can contain sensitive attributes.
