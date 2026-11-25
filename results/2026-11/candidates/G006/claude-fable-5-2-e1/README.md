# app-storage — the standard storage account for an application

Gives one application, in one environment, a place to keep its files (user
uploads, images and videos, generated reports and exports) in its own resource
group. You say **where**, **who** and **what**; the module decides the rest.

```hcl
# orders-prod.tfvars
resource_group_name      = "orders-prod"                            # where: the app's resource group
application_principal_id = "3f2a6c1e-8b4d-4e7a-9c5f-1d2e3a4b5c6d"   # who:   object ID of the app's identity
containers = {                                                      # what:  the "folders" the app needs
  uploads = {}
  exports = { delete_after_days = 30 }                              # regenerable files clean themselves up
}

# where the application runs, so it can reach its files (see "Network")
allowed_subnet_ids = [
  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>",
]
```

```sh
tofu init
tofu plan  -var-file=orders-prod.tfvars
tofu apply -var-file=orders-prod.tfvars
```

Use one state per application and environment (add your team's backend
configuration; none is hard-coded here). `minimal.tfvars` is the smallest valid
input; `examples/full.tfvars` shows every option.

## Using it from the application

There is **no key and no connection string**. Point the Azure SDK at the
`blob_endpoint` output and let it authenticate as the application's identity
(`DefaultAzureCredential`; workload identity on AKS, managed identity on App
Service). The `app_settings` output is a ready-made map of the two non-secret
values the application needs.

If the application hands out download/upload links, sign them with a *user
delegation* key (the SDK's `get_user_delegation_key`), which works with the
application's identity. Account-key SAS tokens do not work, by design.

## What the module decides for you

| Area | Decision |
| --- | --- |
| Placement | In the existing resource group, in its region, inheriting its tags. The resource group is looked up, never created. |
| Name | Derived from the resource group (`orders-prod` → `stordersprod<6 hex>`): valid, globally unique, stable. |
| Access | Entra ID only. Account keys, account-key SAS, anonymous/public containers and SFTP local users are all disabled. The application's identity gets *Storage Blob Data Contributor* on this account; optional groups get read-only. |
| Network | Closed by default. Reachable only from the subnets / private endpoint / IP ranges you list. Opening it to all networks is an explicit flag. |
| Encryption | HTTPS only, TLS 1.2+, encryption at rest with an additional infrastructure layer. |
| Durability | GZRS: three zones plus a second region. |
| Oops-protection | Blob versioning, 30-day soft delete for files and containers, point-in-time restore. Optional delete lock. |
| Cost hygiene | Previous versions are removed after 90 days. Per container you can expire files or move them to the cool tier. |
| Audit | Optional: write/delete logs to a Log Analytics workspace. |

## Network

A new account is unreachable until you tell the module where the application
runs (the plan prints a warning while that is the case):

- `allowed_subnet_ids` — the AKS node subnet and/or the App Service
  VNet-integration subnet. The subnet needs the `Microsoft.Storage` service
  endpoint.
- `private_endpoint_subnet_id` (+ `private_dns_zone_id`) — if your platform uses
  Private Link.
- `allowed_ip_ranges` — e.g. an office range for people who need to browse files.
- `allow_public_network_access = true` — only when browsers or other internet
  clients must reach the files directly. Identity is still required; set
  `cors_allowed_origins` for browser access.

## Operations notes

- The identity running `tofu apply` needs to create role assignments on the
  storage account (Owner, User Access Administrator, or Role Based Access
  Control Administrator in addition to Contributor). `delete_lock_enabled`
  additionally needs permission to manage locks (Owner / User Access
  Administrator).
- `application_principal_id` is the **object ID** of the managed identity or
  service principal, not the client/application ID.
- With `delete_lock_enabled = true`, removing a container or changing who has
  access is deliberately a two-step change: set it to `false`, apply, make the
  change, set it back.
- If the region has no availability zones, set `replication_type = "GRS"`.
- To adopt an account that was created by hand, set `storage_account_name` and
  `tofu import azurerm_storage_account.this <resource id>`. Encryption
  infrastructure settings cannot be changed on an existing account, so the plan
  may propose a replacement — review it before applying.
