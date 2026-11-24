# Standard Application Asset Bucket (S3)

The standard, blessed way for an application team to get an S3 bucket for its
application's assets: user uploads, images and video, generated files, logs.
The module encodes our security, durability and cost defaults so you don't
have to know S3 to do the right thing — give it a name, apply, done.

## Quick start

```hcl
module "assets" {
  source = "./standard-s3-bucket"

  name        = "invoice-service" # required: your app or asset set
  environment = "prod"            # optional, defaults to "dev"
}
```

You never invent a bucket name. The module generates one that is globally
unique, predictable and self-describing:

```
<name>-<environment>-<aws-account-id>-<region>
e.g. invoice-service-prod-123456789012-eu-west-1
```

## What the module decides for you

| Topic | Decision | Why |
| --- | --- | --- |
| Public access | Fully blocked, no opt-out | Asset buckets are never public. Serve content via signed URLs or a CDN. |
| ACLs | Disabled (`BucketOwnerEnforced`) | ACLs are a legacy footgun; access is granted only via IAM and bucket policy. |
| Encryption at rest | AES-256 server-side encryption on everything | Encrypted by default, with zero keys for you to manage. |
| Encryption in transit | Bucket policy denies all non-TLS requests | Data in flight is always encrypted. |
| Versioning | Enabled | Accidental overwrites and deletes can be undone. |
| Lifecycle | Aborts incomplete multipart uploads after 7 days; prunes noncurrent object versions after 30 days | Prevents invisible storage-bill leaks while keeping a 30-day safety net. |
| CORS | Off unless you list browser origins | Locked down until you explicitly need browser access. |
| Naming | Deterministic, includes account id and region | Globally unique, no collisions, obvious owner. |
| Tags | `Application`, `Environment`, `ManagedBy`, `Module` | Findable and auditable; your `tags` merge over these. |

## Inputs

Required:

| Name | Type | Description |
| --- | --- | --- |
| `name` | `string` | Application / asset name; part of the generated bucket name (2-24 chars, `a-z0-9-`). |

Optional (defaults are the recommended setup):

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `environment` | `string` | `"dev"` | Environment label; part of the bucket name. |
| `tags` | `map(string)` | `{}` | Extra tags; override the module's standard tags. |
| `region` | `string` | ambient `AWS_REGION` | Region the bucket is created in. |
| `versioning_enabled` | `bool` | `true` | Keep old object versions as an undo mechanism. |
| `object_expiration_days` | `number` | `null` (keep forever) | Auto-delete objects N days after creation — for logs, scratch and generated files. |
| `cors_allowed_origins` | `list(string)` | `[]` | Browser origins allowed `GET`/`HEAD`/`PUT` via CORS. |
| `access_log_bucket` | `string` | `null` | Existing bucket to receive server access logs. |
| `force_destroy` | `bool` | `false` | Allow destroying the bucket while it still has objects (throw-away dev buckets only). |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_name` | Name of the bucket. |
| `bucket_arn` | ARN of the bucket. |
| `bucket_domain_name` | Global domain (`<bucket>.s3.amazonaws.com`). |
| `bucket_regional_domain_name` | Region-specific domain. |
| `bucket_region` | Region the bucket lives in. |
| `app_access_policy_json` | Ready-to-attach IAM policy granting your app role read/write access. |

## Deliberately not possible

- Making the bucket public (there is no variable for it).
- Disabling encryption at rest.
- Using S3 ACLs for access control.

If you believe you need one of these, talk to the platform team before
reaching for a hand-rolled bucket.
