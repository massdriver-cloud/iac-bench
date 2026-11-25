# Standard Application S3 Bucket Module

The standard OpenTofu root module for provisioning application asset buckets (user uploads, images/videos, generated files, and logs). Application teams only need to provide `app_name` and `environment` (plus an optional `usage_profile`), and the module handles S3 security, encryption, lifecycle cost optimization, and least-privilege IAM policies automatically.

## Quick Start

Copy `minimal.tfvars` and fill in your application name and environment:

```hcl
app_name    = "checkout-api"
environment = "prod"
```

### Common Examples

**1. User uploads with browser direct-upload CORS:**
```hcl
app_name             = "portal-web"
environment          = "prod"
purpose              = "user-uploads"
usage_profile        = "uploads"
cors_allowed_origins = ["https://app.example.com"]
```

**2. Media (images & videos) served via CloudFront OAC + async EventBridge processing:**
```hcl
app_name                     = "media-service"
environment                  = "prod"
purpose                      = "media"
usage_profile                = "media"
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"]
enable_eventbridge           = true
```

**3. Application logs with KMS encryption and 90-day retention:**
```hcl
app_name        = "billing-worker"
environment     = "prod"
purpose         = "logs"
usage_profile   = "logs"
expiration_days = 90
kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
```

## Opinionated Defaults Built In

- **Zero public access**: `aws_s3_bucket_public_access_block` blocks all public ACLs and policies unconditionally.
- **ACLs disabled**: `BucketOwnerEnforced` ownership controls eliminate cross-account object ownership issues.
- **Encryption at rest & in transit**: SSE-S3 (`AES256`) or optional SSE-KMS (`aws:kms`) with S3 Bucket Keys enabled, plus a bucket policy denying all non-HTTPS (`aws:SecureTransport = false`) requests.
- **Workload-tuned lifecycle rules**: Automatic cleanup of incomplete multipart uploads, storage-class transitions gated on `>= 128 KiB` objects, bounded noncurrent version retention, and orphan delete-marker cleanup.
- **Least-privilege IAM outputs**: Ready-to-use `read_only_policy_json`, `write_only_policy_json`, and `read_write_policy_json` outputs (automatically including KMS permissions when `kms_key_arn` is provided).
