# Application file storage

Use this root once per application environment, with separate OpenTofu state for each. It creates Blob Storage for uploads and other application objects, not a mounted file share. It reads the existing group and uses its region and tags.

Copy `minimal.tfvars` to `app.tfvars`. Replace `orders-staging` with your existing group name and the UUID with the **principal (object) ID** of the identity used by your workload. This is not the application/client ID or tenant ID. The workload identity binding on AKS or managed identity on App Service must already be configured.

With Azure credentials and `ARM_SUBSCRIPTION_ID` set in your environment:

```sh
tofu init
tofu plan -var-file=app.tfvars -out=app.plan
tofu apply app.plan
```

The deploying identity needs permission to read the group, manage storage, and create role assignments there. Do not give those deployment permissions to the application. Protect state and plan files; the provider can store sensitive attributes in them.

**In your app:** Pass `blob_service_endpoint` and an Azure Identity SDK credential (such as `DefaultAzureCredential`) to a Blob service client, then select `container_name`. The app can read, write, and delete blobs in that container without an account key or connection string. Allow time for a new role assignment to propagate.

**Defaults:** The HTTPS endpoint is reachable without VNet integration so both platforms can connect. Reachability does not grant access: anonymous blob reads and shared-key authorization are disabled. Standard Hot storage with local redundancy keeps costs down for frequently accessed files; it does not provide regional disaster recovery. Blob and container soft deletion are enabled for 14 days. Previous block blob versions older than 30 days since creation are eligible for cleanup; live files do not expire. These protections are not backups against account deletion. Do not destroy an environment's state-managed resources while the data is needed.
