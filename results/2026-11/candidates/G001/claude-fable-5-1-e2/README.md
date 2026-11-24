# app-assets-bucket

The standard way an application team gets an S3 bucket for its application's assets
(user uploads, images, video, generated files, logs). Fill in two inputs; the module
makes every other decision.

## Quick start

```hcl
# terraform.tfvars (or minimal.tfvars)
application = "photo-service"
environment = "dev"
```

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Then attach `read_write_policy_arn` to your application's IAM role and put
`bucket_name` in your application config. That's it.

Bucket name is `<application>-<environment>-<account id>-<region>`, e.g.
`photo-service-dev-123456789012-us-east-1`. Credentials and region come from the
environment (`AWS_REGION`, profile, etc.); set `region` only to override.

## What you get, without asking for it

| Concern | Decision |
|---|---|
| Public access | Blocked at every level. Serve assets via your app, pre-signed URLs, or CloudFront. |
| ACLs | Disabled (`BucketOwnerEnforced`). Access is governed by IAM/bucket policy only. |
| Encryption at rest | Always on. SSE-S3 by default; pass `kms_key_arn` for SSE-KMS (bucket keys enabled). Uploads that request a *different* algorithm are rejected. |
| Encryption in transit | Bucket policy denies non-TLS and TLS < 1.2 requests. |
| Versioning | Enabled, so overwritten/deleted objects are recoverable. Old versions are purged after `noncurrent_version_retention_days` (30). |
| Housekeeping | Abandoned multipart uploads aborted after 7 days; orphaned delete markers removed. |
| Cost | Objects move to Intelligent-Tiering automatically (`intelligent_tiering = false` to opt out). |
| Tags | `Application`, `Environment`, `ManagedBy` on everything, plus whatever you pass in `tags`. |
| IAM | Two managed policies (`.../<bucket>-read-write`, `.../<bucket>-read-only`) scoped to this bucket. |

## Common tweaks

```hcl
# Disposable data such as logs or exports: delete after 90 days.
expire_objects_after_days = 90

# Browser uploads / direct fetches from a web front end.
cors_allowed_origins = ["https://app.example.com"]

# Regulated data: use your team's KMS key.
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-..."

# Centralised access logs.
access_log_bucket_name = "org-s3-access-logs-123456789012"

# Throwaway environments only.
force_destroy = true
```

## Inputs

| Name | Required | Default | Purpose |
|---|---|---|---|
| `application` | yes | – | Owning application; 2-24 chars `[a-z0-9-]`. |
| `environment` | yes | – | `dev`, `staging`, `prod`, ...; 2-10 chars `[a-z0-9]`. |
| `region` | no | env | AWS region override. |
| `tags` | no | `{}` | Extra tags. |
| `kms_key_arn` | no | `null` | Customer-managed KMS key for SSE-KMS. |
| `noncurrent_version_retention_days` | no | `30` | How long old object versions are kept. |
| `expire_objects_after_days` | no | `null` | Delete current objects after N days. |
| `intelligent_tiering` | no | `true` | Auto-tier objects to cut storage cost. |
| `cors_allowed_origins` | no | `[]` | Browser origins allowed to call the bucket. |
| `access_log_bucket_name` | no | `null` | Existing bucket to receive access logs. |
| `create_access_policies` | no | `true` | Create the read-write / read-only IAM policies. |
| `force_destroy` | no | `false` | Allow destroy with objects present. |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_regional_domain_name`, `bucket_region`,
`read_write_policy_arn`, `read_only_policy_arn`, `read_write_policy_json`,
`read_only_policy_json`, `encryption`.
