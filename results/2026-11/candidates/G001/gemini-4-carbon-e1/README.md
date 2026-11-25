# Standard Application Assets S3 Bucket Module

The paved-road OpenTofu module for application S3 buckets (user uploads, images and videos, generated files, and logs). Provide `app_name` and `environment`, and the module handles security, encryption, versioning, lifecycle cost optimization, and application IAM policies automatically.

## Quick Start (90% of use cases)

```hcl
module "assets_bucket" {
  source = "./path/to/app-bucket-module"

  app_name    = "checkout-service"
  environment = "prod"

  # Optional: attach read/write permissions directly to your app's IAM role
  read_write_iam_role_names = [aws_iam_role.checkout_task_role.name]
}
```

Pass `module.assets_bucket.app_environment_variables` (`S3_BUCKET_NAME`, `S3_BUCKET_REGION`, `S3_BUCKET_ARN`) to your container, pod, or Lambda environment, or attach `module.assets_bucket.read_write_iam_policy_arn` / `module.assets_bucket.read_only_iam_policy_arn` to any IAM role.

## Common Recipes

### Browser Direct Uploads (Presigned URLs + CORS)

```hcl
module "user_uploads" {
  source = "./path/to/app-bucket-module"

  app_name             = "profile-service"
  environment          = "prod"
  purpose              = "uploads"
  cors_allowed_origins = ["https://app.example.com"]
  enable_eventbridge   = true # Trigger async image/video processing via EventBridge
}
```

### Media Bucket Served Behind CloudFront (OAC) + Customer-Managed KMS

```hcl
module "media_bucket" {
  source = "./path/to/app-bucket-module"

  app_name                     = "catalog-service"
  environment                  = "prod"
  purpose                      = "media"
  create_kms_key               = true
  cloudfront_distribution_arns = [aws_cloudfront_distribution.cdn.arn]
}
```

### Generated Exports or Application Logs (Automatic Expiration)

```hcl
module "exports_bucket" {
  source = "./path/to/app-bucket-module"

  app_name               = "reporting-service"
  environment            = "prod"
  purpose                = "exports"
  object_expiration_days = 30
}
```

## What You Get Out of the Box

- **Globally unique deterministic naming**: `<app_name>-<purpose>-<environment>-<account_id>-<region>` (automatically hashed/truncated safely if > 63 characters).
- **Private & ACL-free**: All four S3 Public Access Block settings enabled; `BucketOwnerEnforced` object ownership disables legacy ACLs.
- **Encrypted at rest & in transit**: Default SSE-S3 (`AES256`) or one-flag rotated KMS CMK (`create_kms_key = true` with S3 Bucket Keys enabled); bucket policy denies HTTP and TLS < 1.2 as well as mismatched encryption headers while keeping presigned URLs seamless.
- **Accidental delete/overwrite protection**: Versioning enabled by default; application IAM policies intentionally omit `s3:DeleteObjectVersion` so app bugs or compromised credentials cannot permanently purge historical versions before retention expiry.
- **Zero-surprise cost controls**: Failed multipart uploads aborted after 7 days, objects >= 128 KB automatically enrolled in S3 Intelligent-Tiering (zero retrieval fees, millisecond latency), and noncurrent versions tiered at 30 days and expired at 90 days.
- **Ready-to-use IAM policies**: Scoped `/app-buckets/<bucket>-read-only` and `/app-buckets/<bucket>-read-write` IAM policies (automatically including KMS permissions when SSE-KMS is enabled).
