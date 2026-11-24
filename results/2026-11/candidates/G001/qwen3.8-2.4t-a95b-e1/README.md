# Standard S3 bucket for application assets

The standard way for an application team to get an S3 bucket for its
assets — user uploads, images and video, generated files, logs. Two inputs,
no S3 expertise required: everything else is a deliberate default owned by
this module.

## Usage

```hcl
module "assets" {
  source = "./path/to/this/module"

  application = "photo-service"
  environment = "prod"
}

# Give the application read/write access to its bucket:
resource "aws_iam_role_policy_attachment" "assets" {
  role       = aws_iam_role.app.name
  policy_arn = module.assets.app_policy_arn
}
```

See `minimal.tfvars` in this directory for the smallest valid instantiation.

## What the module decides for you

| Decision | Default | Why |
| --- | --- | --- |
| Bucket name | `{app}-{env}-{account}-{region}-{random}` | Globally unique without any coordination; you can read the owner, environment, account, and region straight off the name. |
| Public access | Blocked on all four settings | Asset buckets are private. Serve public renditions via a CDN or your app. |
| ACLs | Disabled (`BucketOwnerEnforced`) | ACLs are the classic source of per-object permission mistakes; access is granted via IAM, which is auditable. |
| Transport | Bucket policy denies non-TLS | Every request must use HTTPS. |
| Encryption at rest | SSE-S3 (AES-256) | Encrypted by default with zero setup; opt into a customer-managed KMS key via `kms_key_arn`. |
| Versioning | Enabled, old versions pruned after 30 days | An undo button for accidental deletes and overwrites, with a bound on the storage bill. |
| Aborted multipart uploads | Cleaned up after 7 days | Failed uploads otherwise pay for storage forever. |
| Object expiry | Off (keep forever) | Most assets should persist; set `object_expiration_days` for genuinely transient data. |
| CORS | Off | Only enabled when you name the browser origins that talk to S3 directly; backend-issued presigned URLs need none. |
| IAM | Ready-made read/write policy (`app_policy_arn`) | Teams attach one ARN instead of authoring S3 policy JSON. |
| Tags | `Application`, `Environment`, `ManagedBy` + your extras | Every bucket is attributable and cost-allocatable. |

## When you might reach for a knob

- **Throwaway environments:** `force_destroy = true` so destroy doesn't trip
  over leftover objects (default `false` makes destroy fail loudly instead
  of silently deleting data).
- **Transient data:** `object_expiration_days = 7` to auto-delete current
  objects after a week.
- **Direct browser uploads:** `cors_allowed_origins = ["https://app.example.com"]`.
- **Compliance:** `kms_key_arn` for a customer-managed key.
- **A genuinely public bucket:** `allow_public_access = true` — get a
  security review first.

## Outputs

- `bucket_name`, `bucket_arn`, `bucket_domain_name`,
  `bucket_regional_domain_name` — for wiring into your application.
- `app_policy_arn` — the standard read/write IAM policy; attach it to your
  application's role.
