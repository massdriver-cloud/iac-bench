# Standard application asset bucket

An opinionated, private Amazon S3 bucket for application uploads, media, generated files, logs, and similar assets. Application teams provide a globally unique bucket name and basic ownership metadata; the module configures the S3 controls consistently.

This is an asset bucket, not a public static-website bucket. Applications should access it with IAM credentials or presigned URLs. Put a CDN in front of assets that need public distribution rather than making this bucket public.

## Quick start

```hcl
module "assets" {
  source = "./modules/asset-bucket"

  bucket_name = "my-unique-application-assets-production"
  application = "orders"
  environment = "production"
}

output "asset_bucket_arn" {
  value = module.assets.bucket_arn
}
```

Or use this directory directly as a root module:

```shell
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

S3 bucket names are global across AWS. Replace the example name with one your organization can own.

## Decisions made for every bucket

| Control | Default |
| --- | --- |
| Public access | All four S3 public-access-block settings enabled |
| Object ownership | `BucketOwnerEnforced`; ACLs disabled |
| Transport | Bucket policy denies every request where `aws:SecureTransport` is false |
| Encryption | SSE-S3 (`AES256`), with optional customer-managed SSE-KMS |
| Versioning | Enabled; suspension is optional |
| Recovery | Noncurrent versions retained for 90 days |
| Incomplete uploads | Aborted after 7 days |
| Expired delete markers | Removed automatically |
| Current-object retention | Kept unless an explicit prefix expiration rule is supplied |
| Destruction | Protected by `force_destroy = false` |
| CORS | Disabled unless explicitly configured |
| Access logging | Disabled unless a separate destination log bucket is supplied |
| Tags | `Name`, `Application`, `Environment`, and `ManagedBy` always applied |

There are no automatic transitions to archive storage: retrieval latency and minimum-storage charges are workload-dependent. Encryption defaults to SSE-S3 because it provides encryption at rest without KMS request charges. Supplying `kms_key_arn` switches to SSE-KMS and enables an S3 Bucket Key; the key policy must grant the application and required AWS services appropriate access.

## Optional configuration

### Expire logs without expiring user assets

```hcl
expiration_rules = [
  {
    id     = "expire-temporary-logs"
    prefix = "logs/temporary/"
    days   = 30
  }
]
```

With versioning enabled, expiration makes the prior current object noncurrent. The noncurrent copy is removed after `noncurrent_version_retention_days`; retention and recovery windows therefore need to be considered together.

### Browser uploads

```hcl
cors_rules = [
  {
    id              = "application-uploads"
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://app.example.com"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
]
```

CORS controls browser access, not IAM authorization. Keep origins specific and grant upload access with narrowly scoped IAM policies or presigned URLs.

### Customer-managed KMS key

```hcl
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
```

### Server access logs

```hcl
access_logging = {
  target_bucket = "my-central-s3-access-log-bucket"
  # Optional; defaults to s3-access/<this-bucket-name>/
  target_prefix = "s3-access/orders-production/"
}
```

The destination must be a different, existing bucket with a policy that permits S3 log delivery. This module intentionally does not create or modify that central log bucket.

## Inputs

### Required

- `bucket_name` — exact, globally unique bucket name.
- `application` — owning application, used as a mandatory tag.
- `environment` — deployment environment, used as a mandatory tag.

### Optional

| Name | Default | Purpose |
| --- | --- | --- |
| `tags` | `{}` | Additional tags; reserved module tags take precedence |
| `force_destroy` | `false` | Permit deletion of a non-empty bucket during destroy |
| `versioning_enabled` | `true` | Enable versioning; false configures `Suspended` |
| `kms_key_arn` | `null` | Use a customer-managed KMS key instead of SSE-S3 |
| `incomplete_multipart_upload_days` | `7` | Cleanup window for incomplete multipart uploads |
| `noncurrent_version_retention_days` | `90` | Recovery window for overwritten/deleted objects |
| `expiration_rules` | `[]` | Explicit per-prefix current-object expiration |
| `cors_rules` | `[]` | Browser CORS rules |
| `access_logging` | `null` | Existing destination bucket and optional prefix |

## Outputs

- `bucket_id`
- `bucket_name`
- `bucket_arn`
- `bucket_region`
- `bucket_regional_domain_name`

For IAM object permissions, use `"${module.assets.bucket_arn}/*"`; use `module.assets.bucket_arn` for bucket-level actions.

## Operational notes

- The module owns the bucket policy, CORS configuration, lifecycle configuration, encryption configuration, and (when enabled) logging configuration. Do not manage those separately for the same bucket.
- `force_destroy = true` is intended only for disposable environments. It permits irreversible deletion of objects and versions during `tofu destroy`.
- Disabling versioning suspends creation of new versions; it does not re-enable versioning on a bucket where AWS has made that transition irreversible, and it does not delete existing versions.
- Lifecycle deletion is permanent after the configured retention windows. Choose shorter windows only when they match the application's recovery and compliance requirements.
