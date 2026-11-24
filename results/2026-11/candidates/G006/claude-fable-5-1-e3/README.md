# Application storage account

The standard way an application gets Azure Storage for the files it works
with (user uploads, images and videos, generated reports and exports).

You give it three things; the module decides everything else.

```hcl
application_name         = "orders"
environment              = "staging"
application_principal_id = "<object id of the orders app's managed identity>"
```

```sh
tofu init
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## What you get

* A StorageV2 storage account in your application's existing resource group
  (`<application_name>-<environment>`, e.g. `orders-staging`), in that
  resource group's region, named `<app><env><random>` so it is globally unique.
* A private blob container called `files` (pass `containers = ["uploads", "exports"]`
  for more or different ones).
* Your application's identity granted **Storage Blob Data Contributor** on the
  account (`application_can_write = false` makes it Reader instead).

## How your application connects

There are no keys, SAS tokens or connection strings — they are disabled on
the account. Use the `blob_endpoint` output with your identity:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient(account_url=BLOB_ENDPOINT, credential=DefaultAzureCredential())
client.get_container_client("files").upload_blob("report.pdf", data)
```

On AKS use Workload Identity; on App Service use the app's managed identity.
Both are picked up by `DefaultAzureCredential` with no configuration.

## Decisions the module makes for you

| Area | Choice |
|---|---|
| Auth | Entra ID only. Shared keys, SAS, anonymous access, SFTP all off. |
| Transport | HTTPS only, TLS 1.2 minimum. |
| At rest | Microsoft-managed keys plus infrastructure (double) encryption. |
| Redundancy | `prod`: GRS. Everything else: LRS. |
| Accidental deletion | Blob + container soft delete: 30 days in `prod`, 14 days elsewhere. |
| Cost | Hot tier; blobs untouched for 90 days are cooled and re-warmed on next access. |
| Network | Open to all networks by default (still Entra-authenticated). Set `allowed_subnet_ids` and/or `allowed_ip_ranges` to lock it down to those sources. |
| Tags | `application`, `environment`, `managed-by` are always applied; add your own with `tags`. |

## Inputs

| Name | Required | Description |
|---|---|---|
| `application_name` | yes | Short lowercase app name, e.g. `orders`. |
| `environment` | yes | `dev`, `test`, `staging` or `prod`. |
| `application_principal_id` | yes | Object ID of the app's Entra ID identity. |
| `containers` | no | Blob containers to create. Default `["files"]`. |
| `resource_group_name` | no | Override if your RG doesn't follow `<app>-<env>`. |
| `application_can_write` | no | `false` for a read-only app. Default `true`. |
| `allowed_subnet_ids` | no | Subnets allowed through the storage firewall. |
| `allowed_ip_ranges` | no | Public IPs/CIDRs allowed through the storage firewall. |
| `tags` | no | Extra tags. |

## Outputs

`storage_account_name`, `storage_account_id`, `blob_endpoint`,
`container_names`, `container_urls`, `resource_group_name`, `location`.
