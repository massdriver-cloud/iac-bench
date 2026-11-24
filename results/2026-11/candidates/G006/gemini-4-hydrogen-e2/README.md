# Standard Application Storage Account (OpenTofu)

Standardized Azure Blob Storage module for application teams running on AKS and App Service.

## Quick Start

Copy `minimal.tfvars` (or the example below) and fill in your application's four inputs:

```hcl
application_name    = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
principal_id        = "11111111-1111-1111-1111-111111111111" # App's Entra ID identity Object ID
```

Run with OpenTofu:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Connecting from AKS / App Service

Shared access keys and connection strings are disabled. Use the `primary_blob_endpoint` output with `DefaultAzureCredential` from the Azure Storage SDK for your language:

- **AKS**: Ensure Workload Identity is configured for your ServiceAccount and pass its Entra ID principal ID as `principal_id`.
- **App Service**: Enable the app's Managed Identity and pass its Entra ID principal ID as `principal_id`.
- **Direct browser uploads/downloads**: Your application has `Storage Blob Data Contributor` permission, which allows it to mint short-lived **User Delegation SAS** URLs when needed. Set `cors_allowed_origins` if browsers upload or fetch blobs directly.

## Opinionated Defaults

| Decision | Default Behavior | Rationale |
|---|---|---|
| Account kind & tier | `StorageV2`, `Standard`, `Hot` | Supports blob tiering, versioning, soft delete, and lifecycle policies. |
| Account naming | `st<app><env><6-char-hash>` | Guaranteed 3–24 lowercase alphanumeric chars and deterministic uniqueness. |
| Authentication | Entra ID only (`shared_access_key_enabled = false`, `default_to_oauth_authentication = true`) | Eliminates static secrets and connection strings; grants `Storage Blob Data Contributor` to `principal_id`. |
| Public access | `allow_nested_items_to_be_public = false`; all containers `private` | Prevents accidental public exposure of user uploads or reports. |
| Encryption & TLS | HTTPS-only, TLS 1.2 minimum, infrastructure double-encryption enabled | Enforces encryption in transit and at rest without configuration. |
| Redundancy | `ZRS` in `prod`; `LRS` in `dev`/`test`/`staging`/`uat` | Zone-redundant durability in production, cost-effective local redundancy in lower environments. |
| Accidental deletion protection | Versioning + soft delete (30d blobs/containers + 14d PITR in `prod`; 7d in non-prod) | Recovers from accidental overwrites or deletes; old versions/snapshots expire after 90 days. |
| Cost optimization | Lifecycle policy moves unaccessed blobs to Cool (30d) and Cold (90d), auto-tiers back to Hot on read | Keeps active uploads/media fast while lowering cost for older exports and archives. |
| Network firewall | Open to authenticated Entra ID traffic by default; auto-switches to `Deny` when `allowed_subnet_ids` or `allowed_ip_rules` are supplied | Works out-of-the-box for App Service/AKS while supporting VNet locking with a single list input. |
