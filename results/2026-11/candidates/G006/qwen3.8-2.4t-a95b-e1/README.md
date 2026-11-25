# Standard Application Storage (Azure)

This OpenTofu module is the standard way for an application team to get an
Azure storage account for the files its application stores and works with:
user uploads, images and videos, generated reports and exports.

You provide four inputs. The module makes every other decision for you, and
this README documents those decisions.

## Quickstart

```hcl
module "storage" {
  source = "<this module>"

  application_name = "orders"
  environment      = "staging"
  location         = "westeurope"

  # Object (principal) ID(s) of the identity your app runs as, e.g. its
  # AKS workload identity and/or its App Service managed identity.
  app_identity_principal_ids = ["00000000-0000-0000-0000-000000000000"]
}
```

A copyable version lives in [`examples/basic/`](examples/basic/main.tf), and
`minimal.tfvars` shows the same inputs as a variable file.

## What you get

- **One storage account** (general purpose v2, hot tier) in your
  application's existing resource group. Nothing else is created or managed:
  the module never touches your resource group itself.
- **A standard container layout**: `uploads` (user uploads), `media`
  (images and videos), `reports` (generated reports and exports). All
  containers are private. Need different containers? Pass your own list via
  `containers`.
- **Data access for your app's identity.** Each principal ID you pass is
  granted the built-in **Storage Blob Data Contributor** role on the account.
  Your app authenticates with its own Entra ID identity - there are no
  connection strings and no account keys to leak or rotate.
- **Data protection**: blob versioning plus 7-day soft delete for blobs and
  containers, so an accidental overwrite or delete is recoverable.
- **Cost management**: blobs in `reports` move to the cool tier after 30
  days and to archive after 120 days (toggle:
  `enable_reports_lifecycle_policy`).
- **Standard tags**: `application`, `environment`, `managed_by`, `module`,
  plus anything you add via `extra_tags`.

## Design decisions

- **No shared keys.** `shared_access_key_enabled` is off, anonymous access is
  blocked, HTTPS and TLS 1.2 are enforced. Every application already has an
  identity in Entra ID, and both AKS (workload identity) and App Service
  (managed identity) can authenticate to Azure Storage with it. In your code,
  use the account's blob endpoint with `DefaultAzureCredential` (or your
  language's equivalent) instead of a connection string. If you need another
  container, add it to `containers` and re-apply - apps intentionally cannot
  create containers at runtime.
- **Access stays at the data plane.** Identities get *Storage Blob Data
  Contributor*, not control-plane roles, so an app can read/write blobs but
  cannot change account settings or containers.
- **LRS replication by default.** Locally redundant storage is the sensible
  baseline for application data (uploads can usually be re-uploaded, reports
  can be regenerated). Set `replication_type` to `ZRS` if you need zone
  redundancy.
- **Public network access is enabled** so the module works out of the box
  from AKS and App Service without any networking inputs. Access still
  requires the app's identity. Private endpoints / network restrictions are
  an infrastructure-team follow-up, deliberately not required here.
- **Deterministic naming.** The account name is derived from
  `<application><environment>` with non-alphanumerics removed and truncated
  to 24 characters (e.g. `ordersstaging`). Storage account names are globally
  unique in Azure - if yours is taken, set `storage_account_name`.
- **No resource group creation.** Storage lands in the resource group your
  application already owns (default name `<application>-<environment>`,
  e.g. `orders-staging`; override with `resource_group_name`).

## Finding your application's principal ID

Use the object/principal ID (a GUID), not a client/application ID:

```bash
# Managed identity (App Service, or an AKS workload identity's user-assigned identity)
az identity show --name <identity-name> --resource-group <rg> --query principalId

# App registration / service principal
az ad sp show --id <app-id> --query id
```

## Inputs

| Name | Required | Default | Description |
|---|---|---|---|
| `application_name` | yes | - | Application name, e.g. `"orders"`. |
| `environment` | yes | - | Environment, e.g. `"staging"`, `"prod"`. |
| `location` | yes | - | Azure region, e.g. `"westeurope"`. Use your app's region. |
| `app_identity_principal_ids` | yes | - | Object (principal) IDs granted Storage Blob Data Contributor. |
| `resource_group_name` | no | `<application_name>-<environment>` | Existing resource group for the storage account. |
| `containers` | no | `["uploads", "media", "reports"]` | Blob containers to create (all private). |
| `replication_type` | no | `LRS` | `LRS`, `ZRS`, `GRS`, `GZRS`, `RA-GRS`, `RA-GZRS`. |
| `storage_account_name` | no | derived | Explicit account name override. |
| `enable_reports_lifecycle_policy` | no | `true` | Cool/archive aging for the `reports` container. |
| `extra_tags` | no | `{}` | Additional tags. |

## Outputs

| Name | Description |
|---|---|
| `storage_account_id` | Resource ID of the storage account. |
| `storage_account_name` | Account name. |
| `resource_group_name` | Resource group the account was placed in. |
| `primary_blob_endpoint` | Blob endpoint to configure in your app. |
| `containers` | Map of container name => container resource ID. |
