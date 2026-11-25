# Standard application asset bucket

The standard way for an application team to get an S3 bucket for its assets
(user uploads, images/videos, generated files, logs). You supply a name; the
module makes every other decision for you.

## Quick start

```hcl
module "assets" {
  source = "./path/to/this/module"

  name = "checkout-uploads" # your app / asset purpose

  tags = {
    team        = "checkout"
    environment = "prod"
  }
}
```

Wire `module.assets.bucket_name` into your application config and grant your
app's IAM role access to `module.assets.bucket_arn` (and `"<arn>/*"` for
objects). That's it.

## What you get, always

- **Globally unique name** — AWS generates a suffix from your `name` prefix,
  so you never fight over bucket names.
- **Private, full stop** — all four public-access blocks on, ACLs disabled
  (`BucketOwnerEnforced`). Access is IAM-only.
- **Encrypted at rest** — AES256 by default, applied even to uploads that send
  no encryption headers. Pass `kms_key_arn` for a customer-managed key
  (S3 Bucket Keys are enabled to keep KMS costs down).
- **Encrypted in transit** — bucket policy denies any non-TLS request, and
  rejects uploads that explicitly request the wrong encryption algorithm.
- **Versioning on** — overwrites and deletes are recoverable. Old versions
  tier to STANDARD_IA after 30 days and are deleted after 90 days
  (`noncurrent_version_expiration_days`).
- **No invisible cost leaks** — incomplete multipart uploads are aborted
  after 7 days; current objects tier to STANDARD_IA after 90 days
  (`infrequent_access_transition_days`, set `null` to disable).
- **No surprise data loss** — objects are never expired unless you opt in
  with `expiration_days` (use it for logs/disposable data), and
  `force_destroy` is off unless you opt in (scratch buckets only).

## Inputs

| Name | Required | Default | Purpose |
|------|----------|---------|---------|
| `name` | yes | — | Bucket name prefix: lowercase letters/numbers/hyphens, 1–30 chars |
| `tags` | no | `{}` | Extra tags (Name and ManagedBy are always added) |
| `kms_key_arn` | no | `null` (AES256) | Customer-managed KMS key ARN |
| `force_destroy` | no | `false` | Allow deleting a non-empty bucket |
| `infrequent_access_transition_days` | no | `90` | Tier current objects to IA (≥ 30, or `null` to disable) |
| `expiration_days` | no | `null` | Delete current objects after N days (opt-in) |
| `noncurrent_version_expiration_days` | no | `90` | Delete superseded versions after N days |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_regional_domain_name`, `sse_algorithm`.

## Examples

Logs bucket that keeps 30 days of data and can be torn down in CI:

```hcl
module "logs" {
  source = "./path/to/this/module"

  name            = "checkout-logs"
  expiration_days = 30
  force_destroy   = true
}
```

Regulated data with a customer-managed key, kept in STANDARD and forever:

```hcl
module "records" {
  source = "./path/to/this/module"

  name                            = "checkout-records"
  kms_key_arn                     = "arn:aws:kms:us-east-1:123456789012:key/..."
  infrequent_access_transition_days = null
}
```
