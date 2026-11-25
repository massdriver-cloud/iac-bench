# Application blob storage

Deploy once per application environment, with separate OpenTofu state for each deployment. This creates a Blob Storage container for uploads and generated files, not a mounted filesystem. The resource group and application identity must already exist.

## Deploy

1. Copy `minimal.tfvars` to `app.tfvars`. Replace `orders-staging` with the existing group name and replace the sample UUID with the **principal/object ID** of the identity your app runs as (not the application/client ID).
2. Authenticate the deployment environment to Azure and set `ARM_SUBSCRIPTION_ID` to the resource group's subscription. The deployer needs storage management permissions and permission to assign roles in that group. Keep the state in access-controlled storage.
3. Review and apply:

   ```sh
   tofu init
   tofu plan -var-file=app.tfvars -out=app.plan
   tofu apply app.plan
   tofu output
   ```

## Use from the application

Pass `blob_service_url` to the Azure Blob SDK with `DefaultAzureCredential` and select the container named by `container_name`. Configure your pod to use its existing AKS workload identity, or attach the managed identity to App Service. For a user-assigned identity, select the appropriate client ID in the SDK credential configuration. No connection string is needed. The app receives Storage Blob Data Contributor on `files` only; allow time for Azure RBAC to propagate after deployment.

## Defaults and limits

The account inherits the group's region and tags. A hash of the group resource ID gives it a stable storage-compatible name. Standard Hot locally redundant storage keeps frequently accessed objects inexpensive, but does not provide zone or region failover. The HTTPS endpoint is network-reachable without VNet configuration; blobs are not anonymous. TLS 1.2 or later and Entra authorization are required for normal app access; Shared Key is disabled.

Blob and container soft delete retain deleted data for 14 days. Versioning protects against accidental overwrites; previous block-blob versions are eligible for cleanup once 30 days old. Current files do not expire. These controls are not a backup against storage account deletion: destroying the deployment removes the account and its contents.
