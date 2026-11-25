# Standard Application Asset S3 Bucket Module

An opinionated OpenTofu root module for creating production-ready S3 buckets for application assets (user uploads, images and videos, generated files, and logs).

## What This Module Enforces Automatically

- **Private by default**: All four S3 Public Access Block settings are unconditionally enabled.
- **ACLs disabled (`BucketOwnerEnforced`)**: Prevents cross-account/service object ownership issues.
- **Encryption at rest**: SSE-S3 (`AES256`) by default, or SSE-KMS when `kms_key_arn` is provided, with S3 Bucket Keys enabled.
- **Encryption in transit**: Bucket policy denies all non-HTTPS (`aws:SecureTransport == false`) requests.
- **Cost & hygiene lifecycle rules**:
  - Incomplete multipart uploads are aborted after 7 days.
  - Expired object delete markers are automatically cleaned up when versioning is enabled.
  - Noncurrent versions expire cleanly according to the `use_case` profile.
  - Large objects (>= 128 KB) are tiered appropriately when enabled by the profile.
- **Safe deletion**: `force_destroy` defaults to `false` to prevent accidental data loss.
- **Ready-to-use IAM policies**: Outputs `iam_read_write_policy_json` and `iam_read_only_policy_json` for attaching to your application's IAM role.

## Minimal Usage (`minimal.tfvars`)

```hcl
application = "demo-app"
environment = "dev"
```

Run with:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

## Common Examples

### User Uploads (with browser CORS and EventBridge processing)

```hcl
application          = "profile-service"
environment          = "prod"
purpose              = "uploads"
use_case             = "uploads"
cors_allowed_origins = ["https://app.example.com"]
enable_eventbridge   = true
```

### Media Bucket Served via CloudFront OAC

```hcl
application                  = "catalog"
environment                  = "prod"
purpose                      = "media"
use_case                     = "media"
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"]
```

### Application Logs

```hcl
application = "billing-api"
environment = "prod"
purpose     = "logs"
use_case    = "logs"
```

## `use_case` Profiles

| `use_case` | Versioning | Noncurrent Expiration | Intelligent-Tiering (>=128KB) | Standard-IA (>=128KB) | Current Object Expiration |
| --- | --- | --- | --- | --- | --- |
| `assets` (default) | Enabled | 90 days | 30 days | — | Never |
| `uploads` | Enabled | 90 days | 30 days | — | Never |
| `media` | Enabled | 90 days | 30 days | — | Never |
| `generated` | Enabled | 30 days | — | — | Never |
| `logs` | Suspended | 30 days (if enabled) | — | 30 days | 365 days |

All profile defaults can be individually overridden via `versioning_enabled`, `noncurrent_version_expiration_days`, `intelligent_tiering_days`, and `object_expiration_days`.
