# app-storage: standard blob storage for an application

Creates one Azure storage account for one application in one environment, inside
the application's existing resource group, with the application's Entra ID
identity already granted access.

## Use it

Copy `examples/orders-prod.tfvars`, change the values, plan and apply:

```hcl
application              = "orders"
environment              = "prod"
application_principal_id = "<object ID of the identity the app runs as>"

containers = {
  uploads = {}
  exports = { delete_after_days = 30 }
}

allowed_subnet_ids = ["<ID of the subnet the app runs in>"]
```

Then point the application at the `blob_endpoint` output and let it sign in with
its own identity (`DefaultAzureCredential`). There is no connection string and
no account key to hand over, on purpose.

## What you get without asking

| Area | Decision |
|---|---|
| Placement | In the resource group `<application>-<environment>`, in that group's region. The group is looked up, never created. |
| Name | `st<app><env><hash>`: generated, globally unique, stable between runs. |
| Sign-in | Entra ID only. Account keys, key-signed SAS, SFTP and local users are off. The app identity gets *Storage Blob Data Contributor* on this account only. |
| Exposure | No anonymous access, ever. HTTPS only, TLS 1.2+. Copying/replicating data to or from other tenants is blocked. |
| Network | Firewall denies everything except the subnets / private endpoint / IP ranges you list. With nothing listed the public endpoint is switched off entirely and the plan warns that the app cannot reach its storage yet. |
| Encryption | Encrypted at rest with platform-managed keys, twice (service + infrastructure layer). |
| Oops protection | Versioning, soft delete for blobs and containers, and point-in-time restore: 30 days in prod, 7 days elsewhere (`recovery_days`). |
| Durability | prod: GRS (copies in a second region). Everything else: LRS. (`replication_type`) |
| Cost | Files untouched for 90 days move to the cool tier and come back on first access. Old versions are dropped after the recovery window. Containers with `delete_after_days` clean themselves up. |
| Accidental removal | prod gets a "cannot delete" lock on the account (`delete_lock_enabled`). |
| Audit | Blob writes and deletes go to Log Analytics when `log_analytics_workspace_id` is set. |

## Things worth knowing

- **Network access needs one input.** The module cannot guess where the app runs.
  Give it `allowed_subnet_ids` (the subnets need the `Microsoft.Storage` service
  endpoint) and/or `private_endpoint_subnet_id`. If private-endpoint DNS is not
  handled centrally, also pass `private_dns_zone_ids`.
- **Direct browser uploads/downloads** use short-lived *user delegation* links
  created by the backend with its identity; list the front-end origins in
  `cors_allowed_origins`.
- **The prod delete lock also refuses** removing a container or a read-only
  identity. Set `delete_lock_enabled = false`, apply, make the change, set it back.
- **Changing `environment`, `application` or the resource group** changes the
  generated name, which means a new account. Treat them as fixed.
- **Permissions to run this:** Contributor plus the right to create role
  assignments (Owner / User Access Administrator / RBAC Administrator) on the
  resource group; the prod lock needs the same.
- **Provider settings.** `versions.tf` configures the `azurerm` provider so the
  module can be applied directly. If you call it as a child module instead,
  move that `provider` block (including `storage_use_azuread` and
  `data_plane_available = false`) to the calling configuration.
