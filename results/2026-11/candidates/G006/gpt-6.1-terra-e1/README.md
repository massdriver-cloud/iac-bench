# Application blob storage

This root configuration creates a general-purpose Azure Storage account and one private Blob container in an existing application resource group. It grants the application's existing Entra identity **Storage Blob Data Contributor** on that container, not on the entire account. It is intended for application objects such as uploads and reports, not an SMB/NFS filesystem or an Azure Files share.

## Deploy

Copy `minimal.tfvars` to an environment-specific tfvars file and replace all four values:

```hcl
resource_group_name      = "orders-staging"
location                 = "eastus"
storage_account_name     = "ordersstagingblob123" # globally unique, 3-24 lowercase letters/digits
application_principal_id = "00000000-0000-0000-0000-000000000001" # replace with real object ID
```

The resource group and identity must already exist in the configured subscription/tenant. Set `location` to the resource group's region. Supply the principal **object ID**, not the application/client ID: for AKS this is the principal ID of the managed identity used by workload identity; for App Service use the principal ID of the assigned managed identity. Configure the workload to use that identity separately. The sample ID and name are placeholders, not usable production values. Authenticate the AzureRM provider via the environment (including `ARM_SUBSCRIPTION_ID` for AzureRM 4); the deployment identity needs permission to create and manage storage and to create role assignments at the container scope.

```sh
tofu init
tofu plan -var-file=environment.tfvars
tofu apply -var-file=environment.tfvars
tofu output
```

Use `blob_endpoint` and `container_name` with an Azure Blob SDK and an Entra credential, such as DefaultAzureCredential. The identity can read, write and delete blobs in the container. RBAC can take time to propagate after deployment. Do not use account keys or key-based connection strings; shared-key authorization is disabled. This also rules out service/account SAS; use Entra authorization or a user-delegation SAS where appropriate. No credentials are output. Secure the OpenTofu state and restrict access to it: the provider may still store sensitive account attributes there.

## Defaults and tradeoffs

* Standard StorageV2, Hot tier, locally redundant (LRS), Microsoft-managed encryption at rest. LRS does not protect against regional loss; select a different design if regional disaster recovery is required.
* HTTPS only, TLS 1.2 minimum, anonymous blob access and cross-tenant replication disabled. Blob versioning and 30-day blob and container soft delete help recover accidental changes; versions and retained data incur charges and are not an independent backup. These protections do not protect against deletion of the storage account. Manage backups, retention costs, and account deletion controls separately.
* The public endpoint is reachable from any network by default, so AKS and App Service can connect without bespoke networking. Data still requires Entra authorization; this is **not** a private endpoint. To restrict network access, provide `allowed_subnet_ids` and/or `allowed_ip_ranges`; once either is nonempty the firewall denies all other networks with no trusted-services bypass. Subnets need the Microsoft.Storage service endpoint and correctly configured AKS/App Service networking; IPs must be supported public IPv4 addresses or CIDRs. Include all required workload and operational paths. Private endpoint and DNS provisioning are outside this configuration.
* `container_name` defaults to `app-data`; `tags` defaults to an empty map. Renaming the account or container or destroying this root can destroy application data; plan changes carefully. A globally unique account name cannot be guaranteed by the module and must be chosen by the team.
