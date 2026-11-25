# Application Assets Bucket

The standard way for an application team to get an S3 bucket for its
application's assets: user uploads, images/videos, generated files, logs.

You don't need to know S3. Give the module a name, and it makes the
security and cost decisions for you.

## Quick start

```hcl
# main.tf in your stack
module "assets" {
  source = "git::https://…/assets-bucket.git" # or a local path

  name = "checkout-uploads"
}
```

Then read `module.assets.bucket_name` / `module.assets.bucket_arn` to wire
the bucket into your application config and IAM role. (This repository is
also runnable directly as a root module: `tofu plan -var-file=minimal.tfvars`.)

Copy `minimal.tfvars` for the smallest setup, or `example.tfvars` for a
media bucket with browser uploads and Infrequent-Access tiering.

## What the module always does (no knobs, on purpose)

| Decision | Why |
|---|---|
| Generates a globally-unique bucket name from `name` + random suffix | S3 names are shared across all AWS accounts; hand-picked names collide. Use the `bucket_name` output. |
| Blocks **all** public access (all four S3 public-access-block settings) | The #1 S3 mistake is a public bucket. Serve assets via your app or presigned URLs. |
| Disables ACLs (`BucketOwnerEnforced`) | One access model (IAM), no ACL footguns. |
| Bucket policy denies any non-TLS request | Data must never move in plaintext. |
| Encryption at rest always on | AES256 by default; SSE-KMS + S3 Bucket Key if you pass `kms_key_arn`. |
| Aborts incomplete multipart uploads after 7 days | Abandoned uploads are invisible in the console but billed forever. |
| `force_destroy = false` | Protects you from deleting a bucket that still holds data. |

## What you can tune (all optional)

| Variable | Default | When to touch it |
|---|---|---|
| `tags` | `{}` | Add team / application / environment tags. |
| `kms_key_arn` | `null` (AES256) | Your security team requires a customer-managed key. |
| `versioning_enabled` | `true` | Leave on unless you have a strong reason. Gives undo for overwrites/deletes. |
| `noncurrent_version_expiration_days` | `30` | How long old versions are kept (bounds versioning cost). |
| `abort_multipart_upload_days` | `7` | Rarely needs changing. |
| `expiration_days` | `null` (keep forever) | Set for short-lived data: logs, scratch/generated files. |
| `transition_to_ia_days` | `null` | Set (≥ 30) for large media that's rarely re-read; must be < `expiration_days`. |
| `cors_rules` | `[]` | Only if browsers talk to the bucket directly (presigned uploads). |
| `access_log_target_bucket` / `access_log_target_prefix` | `null` | Your platform team gave you a central access-log bucket. |
| `force_destroy` | `false` | Disposable dev/test buckets only. |

Inputs are validated (name format, KMS ARN shape, S3's 30-day IA minimum,
expiry-after-transition ordering, CORS methods), so mistakes fail at plan
time with a readable message instead of at apply time or in production.

## Outputs

- `bucket_name` — the generated bucket name (use in app config)
- `bucket_arn` — use in IAM policies for your app role
- `bucket_domain_name`, `bucket_regional_domain_name` — endpoint hostnames
- `encryption_algorithm` — `AES256` or `aws:kms`

## Files

- `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf` — the module
- `minimal.tfvars` — smallest valid instantiation (`name` only)
- `example.tfvars` — documented, copy-me example (media bucket)
- `smoke-test-full.tfvars` — exercises every optional code path
