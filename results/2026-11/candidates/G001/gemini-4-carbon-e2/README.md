# Standard Application Assets S3 Bucket Module

Opinionated, secure-by-default OpenTofu module for provisioning Amazon S3 buckets for application workloads — user uploads, images and videos, generated exports, and logs.

## What You Get Out of the Box

With only `app_name` and `environment`, this module configures:

- **Collision-free naming:** Deterministic `<app_name>-<environment>-<purpose>-<account_id>-<region>` naming (always valid, `<= 63` chars, no dots).
- **Private & ACL-free security:** All four S3 Block Public Access settings locked on, legacy ACLs disabled (`BucketOwnerEnforced`), HTTPS/TLS `>= 1.2` enforced in the bucket policy.
- **Encryption at rest:** SSE-S3 (`AES256`) by default, or customer-managed KMS (`create_kms_key = true` or `kms_key_arn`) with **S3 Bucket Keys** automatically enabled to cut KMS request costs by up to 99% and bucket policy guardrails preventing encryption downgrades.
- **Accidental data-loss protection:** Versioning enabled by default; `force_destroy` defaults to `false` and is blocked in `prod` / `production`.
- **Automatic cost hygiene:**
  - Cleans up abandoned multipart uploads after 7 days and removes expired delete markers.
  - Moves objects (`>= 128 KB`) to **S3 Intelligent-Tiering** after 30 days.
  - Transitions overwritten/deleted noncurrent versions to `STANDARD_IA` after 30 days and expires them after 90 days.
- **Ready-to-use IAM policies:** Creates `<bucket>-ro` and `<bucket>-rw` managed IAM policies (including scoped KMS permissions when KMS is enabled) that you can attach directly to your ECS task role, EKS Pod Identity / IRSA role, or Lambda execution role.

---

## Copy-Paste Examples

### 1. Minimal — Standard Application Bucket

```hcl
module "assets_bucket" {
  source = "./path/to/module"

  app_name    = "checkout-api"
  environment = "prod"
}
```

Wire your app's IAM role and SDK environment variable:

```hcl
# Pass module.assets_bucket.bucket_name to your app's S3_BUCKET_NAME env var,
# and attach module.assets_bucket.read_write_policy_arn to your app's IAM role
# (or pass read_write_iam_role_names = [aws_iam_role.app.name] directly).
```

### 2. Browser Uploads, Media Delivery (CloudFront OAC) & Async Processing

```hcl
module "uploads_bucket" {
  source = "./path/to/module"

  app_name                  = "creator-studio"
  environment               = "prod"
  purpose                   = "uploads"
  create_kms_key            = true
  enable_eventbridge        = true # Trigger media processing via EventBridge
  read_write_iam_role_names = ["creator-studio-api"]

  cloudfront_distribution_arns = [
    "arn:aws:cloudfront::123456789012:distribution/E1A2B3C4D5E6F7",
  ]

  cors_rules = [
    {
      allowed_origins = ["https://studio.example.com"]
      allowed_methods = ["GET", "HEAD", "PUT"]
      allowed_headers = ["Content-Type", "x-amz-*"]
    }
  ]
}
```

### 3. Temporary Generated Files / Exports / Logs

```hcl
module "exports_bucket" {
  source = "./path/to/module"

  app_name               = "reporting-service"
  environment            = "prod"
  purpose                = "exports"
  object_expiration_days = 14 # Automatically delete generated reports after 14 days
}
```
