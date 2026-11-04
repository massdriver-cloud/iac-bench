# Standard application assets bucket

The standard way an application team gets an S3 bucket for its assets: user
uploads, images and videos, generated files, logs. You supply a name; the
module makes every other decision, and makes it safely.

## What you get by default

| Decision | Default | Why |
|---|---|---|
| Public access | **Fully blocked** (all four public-access-block switches) | Buckets are private until you explicitly say otherwise |
| Encryption at rest | **SSE-S3** (AES256); SSE-KMS via `kms_key_arn` | Everything encrypted, no key management burden |
| Transport | **HTTPS only** (bucket policy denies `aws:SecureTransport=false`) | No plaintext on the wire |
| Versioning | **Enabled** | An "undo" for overwrites and deletes |
| Old versions | **Expired after 90 days** (+ orphan delete markers cleaned) | Versioning without an ever-growing bill |
| Multipart uploads | **Aborted after 7 days if incomplete** | Invisible uploaded parts still cost money |
| ACLs | **Disabled** (`BucketOwnerEnforced`) | One access model (policies), not two |
| Accidental destroy | **Blocked while the bucket has objects** (`force_destroy = false`) | OpenTofu can't silently delete your data |

## Quick start

```hcl
module "assets" {
  source = "<this module>"

  bucket_name = "acme-shop-assets-prod"
}
```

Or run it directly (as this repo does) with a tfvars file:

```hcl
bucket_name = "acme-shop-assets-prod"
```

Then hand your application the outputs:

```hcl
resource "aws_iam_role_policy" "app_s3" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${module.assets.bucket_arn}/*"
    }]
  })
}
```

## The knobs you might actually touch

```hcl
module "assets" {
  source = "<this module>"

  bucket_name = "acme-shop-assets-prod"

  tags = {
    application = "shop"
    environment = "prod"
    team        = "checkout"
  }

  # Browser-based app uploads straight to S3? List your origins.
  cors_allowed_origins = ["https://app.acme.com"]

  # Compliance wants a KMS key? Hand it over, bucket keys are enabled for you.
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

  # Want server access logs? Point at an existing log bucket.
  access_log_target_bucket = "acme-s3-access-logs"

  # Contents are regenerable build artifacts? Save the version storage.
  # versioning_enabled = false

  # Truly public assets (marketing site images)? Loud, explicit opt-in.
  # Prefer CloudFront + OAC over this; never use it for user data.
  # allow_public_read = true

  # Need to grant access to another account/service? Escape hatch.
  # additional_bucket_policy_json = data.aws_iam_policy_document.extra.json
}
```

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `bucket_name` | `string` | **required** | Globally unique; validated against S3 naming rules |
| `versioning_enabled` | `bool` | `true` | Turn off only for regenerable content |
| `noncurrent_version_expiration_days` | `number` | `90` | Lifetime of old versions |
| `abort_incomplete_multipart_upload_days` | `number` | `7` | Cleanup of abandoned multipart uploads |
| `kms_key_arn` | `string` | `null` | `null` = SSE-S3; set = SSE-KMS with bucket keys |
| `allow_public_read` | `bool` | `false` | Makes every object world-readable. Think hard. |
| `cors_allowed_origins` | `list(string)` | `[]` | Empty = no CORS config |
| `cors_allowed_methods` | `list(string)` | `["GET","PUT","POST","HEAD"]` | Only used when origins are set |
| `access_log_target_bucket` | `string` | `null` | Target must allow `logging.s3.amazonaws.com` delivery |
| `access_log_target_prefix` | `string` | `"<bucket_name>/"` | Prefix inside the log bucket |
| `additional_bucket_policy_json` | `string` | `null` | Extra policy statements merged into the bucket policy |
| `force_destroy` | `bool` | `false` | Allow destroying a non-empty bucket (dev/test only) |
| `tags` | `map(string)` | `{}` | Merged over `{ ManagedBy = "OpenTofu" }` |

## Outputs

| Name | Use it for |
|---|---|
| `bucket_name` | Your application's config / SDK bucket parameter |
| `bucket_arn` | IAM policies (`<arn>` and `<arn>/*`) |
| `bucket_domain_name` | Global HTTPS endpoint |
| `bucket_regional_domain_name` | CloudFront origins, regional HTTPS endpoints |
| `versioning_enabled` | Echo of the input, for dependent logic |

## Notes for app teams

- **Private by default.** Your app reaches objects with its IAM role; your
  users reach them with presigned URLs. That covers almost every real use
  case — reach for `allow_public_read` last.
- **Bucket names are global.** If apply fails with `BucketAlreadyExists`,
  someone else owns that name; pick another one.
- The module's guardrail policy statements (TLS enforcement, public access
  only when opted in) always win over anything in
  `additional_bucket_policy_json`.
