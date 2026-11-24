# Standard application storage

One private, identity-only Azure storage account for an application's files
(uploads, images and videos, reports, exports), created in the application's
existing resource group.

## Use it

```hcl
# orders-prod.tfvars
application = "orders"
environment = "prod"
location    = "westeurope"

# Object ID of the application's Entra ID identity
application_principal_id = "<guid>"

# Subnet for the private endpoint, and the DNS zone that makes the blob URL
# resolve to it from your AKS cluster / App Service
private_endpoint_subnet_id = "/subscriptions/.../subnets/private-endpoints"
private_dns_zone_id        = "/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net"

containers = {
  uploads = {}
  exports = { delete_after_days = 30 }
}
```

```sh
tofu init
tofu apply -var-file=orders-prod.tfvars
```

`minimal.tfvars` is the smallest valid input; `examples/prod.tfvars` shows every
commonly used option.

In the application, use the `blob_endpoint` output with `DefaultAzureCredential`
(workload identity on AKS, managed identity on App Service). There are no
account keys or connection strings.

## What you get without asking

| Area | Standard |
| --- | --- |
| Placement | The application's resource group, `<application>-<environment>` unless `resource_group_name` says otherwise |
| Name | `st<app><env><hash>`, stable and globally unique |
| Who can read/write | Only the application's identity, on the containers created here (`Storage Blob Data Contributor`) |
| Keys / SAS / anonymous access | Disabled |
| Network | No public access; reachable only through the private endpoint |
| Encryption | HTTPS only, TLS 1.2+, encrypted at rest with a second infrastructure layer |
| Redundancy | prod: GZRS (zones + paired region); other environments: LRS |
| Recovery | Versioning, soft delete for blobs and containers (prod 30 days, others 7), point-in-time restore (29 / 6 days) |
| Cost control | Previous versions removed after 90 days (prod) / 14 days; optional per-container expiry |
| Delete protection | `CanNotDelete` lock in prod |
| Audit | Read/write/delete logs to Log Analytics when `log_analytics_workspace_id` is set |

## Deploying identity

The identity running `tofu` needs Contributor plus the right to create role
assignments and locks (Owner, or Contributor + User Access Administrator) on the
application's resource group, and permission to join the private endpoint
subnet and private DNS zone. It does not need data access to the storage
account.
