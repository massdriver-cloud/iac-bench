# Application storage account module

The standard way for an app team to get Azure blob storage for its
application files (uploads, images, videos, reports, exports, ...).

You fill in three obvious inputs; the module makes every other decision.

## Usage

```hcl
# terraform.tfvars (copy this, change three values)
resource_group_name      = "orders-staging"                                  # your app's existing resource group for this environment
environment              = "staging"                                       # dev / staging / prod / ...
application_principal_id = "00000000-0000-0000-0000-000000000000"            # OBJECT ID of your app's Entra ID identity
```

Optional extras (you can ignore all of these):

```hcl
blob_containers   = ["uploads", "reports"]   # private containers created for you
allowed_ip_ranges = ["203.0.113.0/24"]       # lock the account down to these public IPs/CIDRs
tags              = { cost-center = "cc-1234" }
```

Then:

```sh
tofu init
tofu plan  -var-file=terraform.tfvars
tofu apply -var-file=terraform.tfvars
```

## What the module decides for you

| Decision | What you get | Why |
| --- | --- | --- |
| Placement | Account created in your existing resource group, in its region | Storage belongs with the app; no extra region choice |
| Name | `st` + your RG name (compacted) + random suffix, e.g. `stordersstagingab12cd` | Globally unique, 3–24 lowercase alphanumerics, stable across plans |
| Authentication | **Entra ID only** — shared access keys disabled | Your app already has an identity; no connection strings to leak or rotate |
| Authorization | Your app identity gets **Storage Blob Data Contributor** scoped to this account | Read/write/delete blobs, nothing more, nothing subscription-wide |
| Public access | Anonymous blob access off; all containers private | App files are never public by accident |
| Transport | HTTPS only, TLS 1.2 minimum | Baseline security |
| Data protection | Blob versioning + blob/container soft delete (30 days in `prod`, 7 elsewhere) | Recover from accidental deletes/overwrites |
| Redundancy | `ZRS` in `prod`, `LRS` elsewhere | Survive a datacentre outage in prod; keep non-prod cheap |
| Network | Open to authenticated traffic by default (AKS egress IPs are dynamic); deny-by-default if you set `allowed_ip_ranges`; trusted Azure services always bypass | Works out of the box from AKS and App Service, lockable when needed |
| Tags | `application`, `environment`, `managed-by = opentofu`, plus your own | Consistent inventory |

## Connecting from your app (AKS / App Service)

There are **no access keys**. Use the blob endpoint output with your
workload's Entra identity:

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

client = BlobServiceClient(
    account_url="<primary_blob_endpoint output>",
    credential=DefaultAzureCredential(),
)
```

On AKS use workload identity / managed identity; on App Service use the
system- or user-assigned managed identity. Make sure
`application_principal_id` is the **object (principal) ID** of that identity
(not the client/application ID).

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `resource_group_name` | yes | Your app's existing resource group for this environment |
| `environment` | yes | `dev`, `staging`, `prod`, ... (lowercase) |
| `application_principal_id` | yes | Object ID (GUID) of the app's Entra ID identity |
| `blob_containers` | no | Set of private container names to create (default `[]`) |
| `allowed_ip_ranges` | no | Public IPs/CIDRs to restrict access to (default `[]` = open to authenticated traffic) |
| `tags` | no | Extra tags (default `{}`) |

## Outputs

`storage_account_id`, `storage_account_name`, `primary_blob_endpoint`,
`primary_blob_host`, `resource_group_name`, `location`,
`blob_container_names`, `application_role_assignment_id`.

## Notes

- `minimal.tfvars` is the smallest valid instantiation of this module.
- `example.tfvars` shows the optional inputs in use.
- Changing `environment` to/from `prod` changes redundancy and retention in
  place where Azure allows it; changing `resource_group_name` creates a new
  account (data does not move — migrate deliberately).
