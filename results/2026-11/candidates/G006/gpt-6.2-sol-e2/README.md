# Application Blob Storage for Azure

Use this OpenTofu root once per application resource group, with separate state for each environment. It creates one general-purpose v2 storage account in the existing group's region and a private `app-files` blob container. It does not create a resource group, application identity, or network. This is object storage for application files, not an Azure Files mount or a public website.

## Deploy

Copy `minimal.tfvars` and replace its two example values:

```hcl
resource_group_name      = "orders-staging"
application_principal_id = "11111111-2222-4333-8444-555555555555"
```

Use the application's Entra **object (principal) ID**. For an app registration, use the tenant's enterprise application/service principal object ID, not the app registration object ID or application/client ID. For a managed identity, use its principal ID.

With Azure credentials and `ARM_SUBSCRIPTION_ID` in the environment, run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The deployment identity needs to read the existing group, manage storage resources there, and create/delete role assignments on the containers. A storage management role by itself does not grant permission to assign roles. The subscription must already have `Microsoft.Storage` registered and, for private connectivity, `Microsoft.Network`. Use your team's protected, locking state backend for production: although no keys are output and Shared Key access is disabled, AzureRM may still store sensitive account attributes in state. Do not commit state or saved plans.

## Connect the application

Use the `blob_endpoint` and the `container_urls` outputs with the Azure Blob SDK and the application's Entra credential. Configure AKS Workload Identity or the App Service identity separately so the application actually requests tokens as the same principal. Role assignments can take time to propagate. The application can read, write and delete blobs in the provisioned containers; it does not get an account-wide data role, keys, or a connection string from this module. Use the configured container names directly rather than relying on account-wide container discovery.

## What the defaults mean

- **Identity and transport:** HTTPS only, TLS 1.2 or newer, no anonymous blobs and no Shared Key access. In the two-input setup the service endpoint is reachable over the public network, **but the data is not public**: access still requires authorization. Clients using account keys or Shared Key SAS will not work.
- **Private-only networking:** If your environment requires it, add the inputs from `private.example.tfvars` alongside the two required values. This creates a Blob private endpoint and disables the public endpoint. Use an existing eligible subnet and the existing `privatelink.blob.core.windows.net` private DNS zone. The deployer needs permission to join the subnet and use the DNS zone. The workload must have a route to the endpoint and resolve the standard blob hostname to its private IP; arrange VNet connectivity (including VNet integration for App Service) and private DNS links or forwarding separately. Set `private_endpoint.location` if the subnet's VNet is in a different region from the resource group. The SDK URL does not change.
- **Redundancy:** Standard hot storage with ZRS by default for resilience to a zone outage. Set `replication_type = "LRS"` if ZRS is unavailable in your region or single-location redundancy is acceptable. Neither setting provides cross-region disaster recovery.
- **Recovery and retention:** Blob and container soft delete are enabled for 30 days, and blob versioning is enabled. The lifecycle rule never expires current blobs; it expires previous block blob versions based on **version creation age** (90 days), not how long the version has been noncurrent. A version can therefore qualify shortly after it becomes noncurrent. Versions and soft-deleted data can incur storage costs. These controls are not backups and do not protect against deleting the storage account. Review plans before removing a container or destroying the root.
- **Naming and layout:** The storage account name is derived from the resource group name and full Azure resource ID; no globally unique name is required as input. `container_names` can replace the default with a set such as `["uploads", "reports"]`. Adding a name creates a private container and grants the application access to it; removing a name deletes the container and revokes its assignment. `tags` is optional.
