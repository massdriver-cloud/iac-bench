# Standard S3 application asset bucket

This module creates one private S3 bucket for an application's assets. Application teams provide an application name and environment; the module supplies the security and data-protection defaults.

It is intended for user uploads, media, generated files, and private application logs. It is **not** a public website bucket: public access is always blocked and the module does not configure static website hosting.

## Quick start

```hcl
module "application_assets" {
  # Use the local path where your team stores this module.
  source = "./modules/application-assets"

  application_name = "orders-web"
  environment      = "prod"

  tags = {
    Owner = "orders-team"
  }
}

output "asset_bucket_name" {
  value = module.application_assets.bucket_name
}

output "asset_bucket_arn" {
  value = module.application_assets.bucket_arn
}
```

The calling root module must configure the AWS provider and credentials in the usual way. This module does not create or manage application IAM roles; use `bucket_arn` and `${bucket_arn}/*` when granting the application role only the bucket/object actions it needs.

To plan this directory directly with its smallest valid configuration:

```shell
tofu init
tofu plan -var-file=minimal.tfvars
```

## What the module decides for you

| Setting | Default behavior |
| --- | --- |
| Bucket name | `<application>-<environment>-<12-digit-account-id>-<region>` |
| Public access | All four S3 public-access-block settings enabled; not configurable |
| Object ownership | `BucketOwnerEnforced`; ACLs disabled |
| Transport | Bucket policy denies every S3 request made without TLS |
| Encryption at rest | SSE-S3 (`AES256`); optionally use an existing KMS key |
| Versioning | Enabled |
| Current objects | Retained indefinitely unless expiration is explicitly configured |
| Noncurrent versions | Expired after 90 days |
| Incomplete multipart uploads | Aborted after 7 days |
| Expired delete markers | Removed automatically |
| Destruction | Protected: OpenTofu will not empty a non-empty bucket |
| CORS | Disabled unless rules are supplied |
| Access logging | Disabled unless an existing destination bucket is supplied |
| Tags | `Application`, `Environment`, `ManagedBy`, and `Name` always applied |

SSE-S3 is a sound default for ordinary application assets. If a team needs key rotation control, key-use auditing, or a compliance-mandated key, set `kms_key_arn` to an existing key. S3 Bucket Keys are then enabled automatically. The key policy must allow the relevant S3/application principals to use the key.

## Optional configuration

### Short-lived logs with customer-managed KMS encryption

```hcl
module "log_assets" {
  source = "./modules/application-assets"

  application_name       = "orders-jobs"
  environment            = "prod"
  kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  object_expiration_days = 30

  # Old versions are not useful for this short-lived log bucket.
  noncurrent_version_expiration_days = 7
}
```

Do not set `object_expiration_days` for uploads or other assets that must be retained.

### Browser uploads requiring CORS

CORS is not authentication and does not make a bucket public. Keep origins specific to the application and grant only required methods.

```hcl
cors_rules = [
  {
    id              = "orders-browser-upload"
    allowed_methods = ["GET", "PUT"]
    allowed_origins = ["https://orders.example.com"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }
]
```

### Server access logging

```hcl
access_logging = {
  target_bucket = "existing-central-s3-access-log-bucket"
  target_prefix = "orders-web/prod/"
}
```

The destination must already exist in the same Region and be configured to accept S3 server access log delivery. Do not point a bucket at itself. Logging is optional because most deployments should deliver to a separately governed central log bucket.

### Existing bucket name or additional policy statements

`bucket_name` can adopt a pre-existing compatible name, but the generated name is recommended. `additional_bucket_policy_json` accepts an IAM policy JSON document for exceptional cross-account or service integrations. Its statements are combined with the module's TLS denial; it does not replace that guardrail. Prefer IAM policies on the application role for ordinary access.

## Inputs

Only `application_name` and `environment` are required.

| Name | Type | Default | Purpose |
| --- | --- | --- | --- |
| `application_name` | `string` | required | 3-24 character lowercase application identifier |
| `environment` | `string` | required | 2-10 character lowercase environment identifier |
| `bucket_name` | `string` | `null` | Explicit bucket-name override |
| `tags` | `map(string)` | `{}` | Additional bucket tags |
| `force_destroy` | `bool` | `false` | Allow OpenTofu to empty the bucket during destroy; use only for disposable data |
| `versioning_enabled` | `bool` | `true` | Enable versioning; disabling it suspends versioning |
| `kms_key_arn` | `string` | `null` | Existing KMS key ARN; `null` selects SSE-S3 |
| `object_expiration_days` | `number` | `null` | Optional retention period for current object versions |
| `noncurrent_version_expiration_days` | `number` | `90` | Retention for old versions; `null` retains them indefinitely |
| `abort_incomplete_multipart_upload_days` | `number` | `7` | Cleanup period for interrupted multipart uploads |
| `access_logging` | `object` | `null` | Existing target bucket and optional target prefix |
| `cors_rules` | `list(object)` | `[]` | Browser CORS rules |
| `additional_bucket_policy_json` | `string` | `null` | Additional IAM bucket policy document |

## Outputs

| Name | Purpose |
| --- | --- |
| `bucket_name` | Bucket name for application configuration |
| `bucket_arn` | Bucket ARN for IAM policies |
| `bucket_regional_domain_name` | Regional HTTPS endpoint hostname |
| `bucket_region` | Region selected by the AWS provider |
| `versioning_enabled` | Configured versioning choice |
| `kms_key_arn` | Configured KMS key ARN, or `null` for SSE-S3 |

## Data-safety notes

- With `force_destroy = false`, destroying a bucket that still contains objects or versions intentionally fails. Back up and empty it through a deliberate operational process first.
- Suspending versioning does not remove existing versions. This module also omits the noncurrent-version expiration rule while versioning is disabled; set an explicit cleanup process before disabling versioning on a bucket that already contains old versions.
- Lifecycle expiration is asynchronous. Retention values are safety/cost controls, not exact deletion timestamps.
- Changing a bucket name or Region replaces the bucket. Treat those as immutable after real data is stored.
