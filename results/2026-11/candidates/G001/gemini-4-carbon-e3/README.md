# Standard Application S3 Bucket Module

Opinionated, secure-by-default OpenTofu module for provisioning S3 buckets for application workloads (user uploads, images and videos, generated files, and logs).

## What You Get Out of the Box

- **Collision-free naming:** Automatically names buckets `<app_name>-<purpose>-<environment>-<account_id>-<region>` (truncating deterministically if over 63 characters).
- **Private & modern ownership:** Enforces all four S3 Block Public Access settings and `BucketOwnerEnforced` object ownership (disabling legacy S3 ACLs).
- **Encryption at rest & in transit:** Defaults to SSE-S3 (`AES256`) or optional customer-managed KMS (`create_kms_key = true` or `kms_key_arn`) with S3 Bucket Keys enabled to cut KMS request costs, plus bucket policy guardrails denying HTTP and TLS < 1.2.
- **Data protection & cost hygiene:** Enables versioning (`force_destroy = false` by default), cleans up abandoned multipart uploads after 7 days, expires noncurrent object versions after 90 days, removes orphaned delete markers, and transitions objects >= 128 KiB to S3 Intelligent-Tiering after 30 days.
- **Ready-to-attach IAM policies:** Generates least-privilege `read_only` and `read_write` IAM policies (and JSON documents) automatically scoped to the bucket and its KMS key.
- **Event-ready:** Emits object notifications to Amazon EventBridge by default so async media/file pipelines can subscribe without mutating bucket notifications later.

## Quick Start (Minimal Configuration)

```hcl
app_name    = "checkout-api"
environment = "prod"
```

## Common Recipes

### 1. Browser Direct Uploads (Presigned URLs + CORS)

```hcl
app_name    = "profile-service"
environment = "prod"
purpose     = "uploads"

cors_rules = [
  {
    allowed_origins = ["https://app.example.com"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
  }
]
```

### 2. Temporary Generated Files or Application Logs (Auto-Expiring)

```hcl
app_name    = "billing-worker"
environment = "prod"
purpose     = "generated-exports"

lifecycle_rules = {
  expiration_days = 14
}
```

### 3. Media Assets Served via CloudFront OAC with Dedicated KMS Key

```hcl
app_name       = "media-service"
environment    = "prod"
purpose        = "media"
create_kms_key = true

cloudfront_distribution_arns = [
  "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
]
```

## Wiring Permissions to Your Application Role

Attach the `read_write_policy_arn` (or `read_only_policy_arn`) output directly to your ECS task role, Lambda execution role, or Kubernetes IRSA / Pod Identity role—or pass your role ARN via `read_write_principal_arns` / `read_only_principal_arns` for direct bucket-policy access.
