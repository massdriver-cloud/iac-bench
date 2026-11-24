# Application storage account

This root module provisions one standard-purpose Azure Blob Storage account in an application's existing resource group and grants the application's existing Entra ID identity data access. It does not create an identity, resource group, or containers; the app can create and manage its own private blob containers using its role assignment.

## Inputs

The required inputs are `application_name`, `resource_group_name`, `location`, and `application_principal_id`. The principal ID is the identity's Entra object ID (not its client ID). `tags` is optional.

Example (`minimal.tfvars`):

```hcl
application_name         = "orders"
resource_group_name      = "orders-staging"
location                 = "eastus"
application_principal_id = "11111111-2222-3333-4444-555555555555"
```

Initialize and plan/apply this root module using the Azure credentials available in the environment.

## Defaults and access

The account uses Standard StorageV2, locally redundant storage, and the Hot access tier. HTTPS and TLS 1.2 are required; public blob access, shared-key authentication, and local users are disabled. The account endpoint remains network-accessible so AKS and App Service workloads can connect without this module needing application-specific network inputs; data access is authorized with Entra ID. The module assigns `Storage Blob Data Contributor` at the account scope to the supplied workload identity. Configure network restrictions separately if an environment requires private endpoints or restricted egress.

Blob versioning and seven-day blob/container soft delete are enabled. Previous block-blob versions are removed after 30 days to limit unbounded version retention. The generated storage account name is deterministic for a subscription, resource group, and application name.
