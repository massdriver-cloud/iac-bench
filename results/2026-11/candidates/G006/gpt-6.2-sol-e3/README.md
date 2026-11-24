# Application Blob Storage

This OpenTofu root module provisions one Azure Blob Storage account per application resource group. Use it for uploads, media, reports, and other application objects. It is not an Azure Files share, a filesystem mount, or an App Service content share.

## Deploy

1. Copy `minimal.tfvars` to `app.tfvars` and replace both values. `resource_group_name` is the existing group (for example, `orders-prod`). `application_principal_id` is the **Entra object ID** of the app's service principal or the **principal ID** of its managed identity, not the client ID. The module does not create an identity, a resource group, or an AKS federated credential.
2. Use your pipeline's Azure credentials and target subscription from the environment (including `ARM_SUBSCRIPTION_ID`). The deployment identity needs to read the group, manage the resources being created, and create/delete Azure role assignments at the container scopes. Have `Microsoft.Storage` already registered, and `Microsoft.Network` if using a private endpoint. Protect the OpenTofu state and keep separate state for each application environment.
3. Run:

   ```sh
   tofu init
   tofu plan -var-file=app.tfvars -out=app.tfplan
   tofu apply app.tfplan
   tofu output container_urls
   ```

## Connect the app

Use the URL for `app-data` (or the applicable name from `container_urls`) with an Azure Blob SDK and an Entra token credential. On AKS, configure the pod to use the existing workload identity. On App Service, enable or attach the managed identity and, for a user-assigned identity, configure the SDK to select its client ID. The client ID used by an SDK is distinct from the principal ID supplied to OpenTofu. Allow time for Azure RBAC to propagate after apply.

The app receives **Storage Blob Data Contributor** on each managed container, not on the storage account or resource group. It can read, write, and delete data in those containers; use the known container URLs rather than assuming permission to list all containers. HTTPS with TLS 1.2 or newer is required. Anonymous access and Shared Key authorization (including Shared Key–signed SAS) are disabled. The module outputs URLs and resource identifiers, not credentials.

## Defaults and overrides

- The account's region comes from the existing resource group. Its Azure name is derived from the group's full resource ID, so staging and production get distinct names without needing to pick globally unique names. Use one deployment per group.
- Standard, Hot, locally redundant storage (`LRS`) is the low-cost baseline; it does not protect against a zone outage. Set `replication_type = "ZRS"` for production workloads requiring zone resilience where supported, or select a supported geo-redundant mode if required.
- The module creates one private container, `app-data`. Set `container_names` to create a different set. Removing a container from this set deletes it; review plans for deletes and replacements. Blob and container soft delete are enabled for 30 days. Blob versioning is enabled, with no automatic expiry of previous versions; monitor storage costs for frequently overwritten objects. These settings do not protect against account deletion and are not a backup.
- By default the service endpoint is publicly reachable so it works from AKS and App Service without preconfigured VNet connectivity. The blobs are not public: Azure still requires authorized requests. If your policy requires private connectivity, set `private_network` to an object with `subnet_id` (an existing private endpoint subnet in the deployment subscription) and `private_dns_zone_id` (an existing `privatelink.blob.core.windows.net` private DNS zone). This creates a Blob private endpoint and DNS zone group and disables public network access. The deployment identity needs permission to join the subnet and DNS zone. The AKS or App Service workload must already have a VNet route to the endpoint (for example, App Service VNet integration) and resolve the storage hostname through the linked private DNS zone. Keep using the same Blob URL.
- The account and any private endpoint inherit resource group tags; `tags` adds or overrides them.
