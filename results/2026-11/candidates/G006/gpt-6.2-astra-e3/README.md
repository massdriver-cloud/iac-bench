# Application file storage

Deploy this directory once per app environment, with a separate OpenTofu state for each. You get one Azure Blob Storage account in your existing resource group's region, with a `files` container for uploads, media, reports, and other objects. No file share or volume mount is needed.

1. Copy `minimal.tfvars` to `app.tfvars`. Replace `resource_group_name` with your existing group and `application_principal_id` with your workload identity's **principal/object ID** (not its application/client ID).
2. Authenticate the AzureRM provider in your environment and set `ARM_SUBSCRIPTION_ID` to the group's subscription. The deployment identity must be able to read the group, manage storage, and assign roles there. Use an access-controlled state backend; provider state can contain sensitive attributes.
3. Run:

   ```sh
   tofu init
   tofu plan -var-file=app.tfvars -out=app.plan
   tofu apply app.plan
   tofu output
   ```

Pass `blob_service_url` and `container_name` to your app as configuration. Construct the Azure Blob SDK service client using that HTTPS URL and `DefaultAzureCredential`, then select the named container. Use the AKS workload identity or App Service managed identity already configured for the app. It gets Storage Blob Data Contributor on this container only; new role assignments can take a few minutes to work. No connection string is required.

The account uses Standard hot storage for active files and zone-redundant copies within the region (the group's region must support ZRS). Blob and container soft delete give you 14 days to recover accidental deletions; this isn't a backup against account deletion or regional loss. The account name is derived from the group ID, not the identity, so rotating the app identity changes permissions rather than replacing storage.

The HTTPS endpoint is network-reachable without a VNet so both hosting platforms can connect. That does not make files public: anonymous blob access and Shared Key authorization are disabled, and TLS 1.2 or later is required. If your environment mandates private routing, arrange private endpoint and DNS integration before using this design.
