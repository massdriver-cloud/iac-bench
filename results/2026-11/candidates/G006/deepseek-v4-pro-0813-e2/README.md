# Standard Application Storage Account

A standard, secure-by-default Azure Storage account for application files such as
user uploads, images, videos, reports, and exports.

The module is intended for app teams that already have:

- a resource group named `<application_name>-<environment>` (for example
  `orders-staging`), and
- an Entra ID application identity (managed identity or service principal).

## What it creates

- One general-purpose v2 storage account in the application resource group.
- Private blob containers: `uploads`, `images`, `videos`, `reports`, and
  `exports` (override with `containers`).
- A `Storage Blob Data Contributor` role assignment for the application identity.
- Soft delete for blobs and containers, plus blob versioning, for
  protection against accidental deletion or overwrites.

## Secure defaults

- HTTPS-only and TLS 1.2.
- Anonymous blob public access is disabled.
- Shared access key authentication is disabled; apps use their Entra ID
  identity instead.
- The public Azure endpoint remains enabled so AKS and App Service apps can
  reach storage without private networking. Set `public_network_access_enabled`
  to `false` if private endpoints are in use.

## Example

```hcl
application_name            = "orders"
environment                 = "staging"
app_identity_principal_id   = "00000000-0000-0000-0000-000000000000"
```

With these inputs the module creates `stordersstaging` in resource group
`orders-staging`. The storage account location is read from the resource group
automatically, or can be supplied explicitly with `location`.

If the resource group does not follow the `<application_name>-<environment>`
pattern, set `resource_group_name_override`.
