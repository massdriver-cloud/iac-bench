# Standard Application Assets S3 Bucket

A standard, secure-by-default OpenTofu module for application S3 asset buckets (user uploads, images & videos, generated files, and logs).

## Quick Start

Copy this minimal example and set `app_name` and `environment`:

```hcl
app_name    = "checkout-api"
environment = "prod"
```

## Common Profiles

Set `asset_profile` (and `purpose` if your app owns multiple buckets) to tailor lifecycle and versioning behavior without configuring raw S3 rules:

### User Uploads (with browser CORS for pre-signed URLs)

```hcl
app_name             = "profile-service"
environment          = "prod"
purpose              = "user-uploads"
asset_profile        = "uploads"
cors_allowed_origins = ["https://app.example.com"]
```

### Images & Videos (fronted by CloudFront OAC)

```hcl
app_name                     = "media-service"
environment                  = "prod"
purpose                      = "media"
asset_profile                = "media"
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"]
```

### Generated Files (auto-expire after 90 days by default)

```hcl
app_name      = "reporting-worker"
environment   = "prod"
purpose       = "exports"
asset_profile = "generated"
```

### Application Logs (auto-expire after 365 days by default)

```hcl
app_name      = "billing-api"
environment   = "prod"
purpose       = "logs"
asset_profile = "logs"
```

## Built-In Defaults & Guardrails

- **Private by default**: All four S3 Block Public Access settings enabled; ACLs disabled via `BucketOwnerEnforced`.
- **Encryption in transit & at rest**: Bucket policy denies non-HTTPS (`aws:SecureTransport = false`) requests; SSE-S3 (`AES256`) with S3 Bucket Keys enabled by default (optional `kms_key_arn` for SSE-KMS).
- **Globally unique, valid names**: Automatically constructs `<app>-<env>-<purpose>-<account_id>-<region>` with deterministic hash truncation if over 63 characters.
- **Cost & version hygiene**: Aborts incomplete multipart uploads after 7 days, expires noncurrent versions and orphan delete markers, and transitions objects >= 128 KB to Intelligent-Tiering.
- **App-ready IAM**: Outputs least-privilege `read_only_policy_arn` / `read_write_policy_arn` (and JSON documents) scoped strictly to the bucket.
- **Event-driven ready**: Amazon EventBridge notifications enabled by default.
