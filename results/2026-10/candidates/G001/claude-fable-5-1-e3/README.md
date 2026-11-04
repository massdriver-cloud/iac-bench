# app-assets-bucket

The standard way to get an S3 bucket for your application's assets (uploads,
images, video, generated files, logs). Give it an application name and an
environment; the module decides everything else.

## Quick start

```hcl
application = "photo-gallery"
environment = "dev"
```

That's it. You get a bucket named `photo-gallery-dev-<account-id>-<region>`.

Browser uploads/downloads straight from the bucket? Add your site's origin:

```hcl
cors_allowed_origins = ["https://photos.example.com"]
```

Transient data such as logs or temporary exports? Set a lifetime:

```hcl
object_expiration_days = 90
```

## What you get, without asking

| Concern | Decision |
|---|---|
| Public access | Blocked at every layer. Serve assets through your app or a CDN. |
| Object ownership | `BucketOwnerEnforced` — ACLs disabled, the bucket owner owns everything. |
| Encryption at rest | Always on. SSE-S3 by default; pass `kms_key_arn` for SSE-KMS (with S3 Bucket Keys to keep KMS cost down). |
| Encryption in transit | Bucket policy denies any non-TLS or pre-TLS-1.2 request. |
| Versioning | Enabled. Overwritten/deleted objects are recoverable for `noncurrent_version_retention_days` (default 30). |
| Cost hygiene | Abandoned multipart uploads purged after 7 days; orphaned delete markers cleaned up; objects moved to Intelligent-Tiering so cold data gets cheaper automatically. |
| Naming | `<application>-<environment>-<account-id>-<region>` — globally unique, self-describing, no collisions between accounts or regions. |
| Tags | `Application`, `Environment`, `ManagedBy`, `Module`, plus anything in `tags`. |

## Inputs

| Name | Required | Default | Purpose |
|---|---|---|---|
| `application` | yes | — | Owning application, 1–24 chars `[a-z0-9-]`. |
| `environment` | yes | — | `dev`, `staging`, `prod`, … 1–10 chars `[a-z0-9-]`. |
| `region` | no | provider/env default | Region to create the bucket in. |
| `bucket_name` | no | generated | Escape hatch to override the generated name. |
| `kms_key_arn` | no | `null` (SSE-S3) | Customer-managed KMS key for SSE-KMS. |
| `cors_allowed_origins` | no | `[]` | Exact origins allowed for browser access; `*` is rejected. |
| `cors_allowed_methods` | no | `GET HEAD PUT POST` | Methods permitted for CORS. |
| `object_expiration_days` | no | `null` (keep forever) | Delete current objects after N days. |
| `noncurrent_version_retention_days` | no | `30` | Undo window for overwrites/deletes. |
| `enable_intelligent_tiering` | no | `true` | Automatic storage-class optimisation. |
| `access_log_bucket` | no | `null` | Existing bucket to receive server access logs. |
| `force_destroy` | no | `false` | Allow destroy of a non-empty bucket. Leave off for real data. |
| `tags` | no | `{}` | Extra tags. |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_objects_arn`, `bucket_regional_domain_name`,
`bucket_region`, `encryption`, `kms_key_arn`.

Use `bucket_arn` and `bucket_objects_arn` as the `Resource` list in your
application's IAM policy; if you supplied a KMS key, also grant it
`kms:Decrypt` and `kms:GenerateDataKey` on `kms_key_arn`.
