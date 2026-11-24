# Standard Application Asset S3 Bucket Module

A secure, cost-optimized, and production-ready OpenTofu module designed for application teams storing application assets:
- **User uploads** (documents, avatars, files)
- **Media** (images, audio, video)
- **Generated artifacts** (PDFs, reports, exports)
- **Application logs and ingestion data**

Application developers do not need to be S3 experts. By copying an example and providing just a couple of obvious inputs (`bucket_name` and `environment`), the module applies cloud security best practices, cost controls, and lifecycle policies automatically.

---

## Quick Start: The "Copy & Paste" Example

Most application teams only need this:

```hcl
module "app_assets" {
  source = "./"

  bucket_name = "my-app-assets-production"
  environment = "production"
  application = "checkout-service"
}
```

This single declaration provisions:
- Fully private bucket (S3 Public Access Block enabled across all 4 controls).
- Enforced HTTPS / TLS 1.2+ transport security via bucket policy.
- Modern S3 ownership controls (`BucketOwnerEnforced`), disabling legacy ACLs and ensuring bucket owner ownership.
- AES256 server-side encryption with S3 Bucket Keys enabled.
- S3 Object Versioning enabled for protection against accidental deletion and overwrites.
- Automated lifecycle management:
  - Aborts incomplete multipart uploads after 7 days (prevents runaway costs from interrupted large-file uploads).
  - Transitions previous (noncurrent) object versions to Standard-IA after 30 days.
  - Automatically deletes noncurrent versions after 90 days.
  - Cleans up expired object delete markers.
- Pre-built IAM policies for application access (read-only, read-write, write-only).

---

## Common Use Cases & Recipes

### 1. Direct Browser Uploads / Media (with CORS)
For applications that let users upload files or stream media directly via presigned URLs:

```hcl
module "user_uploads" {
  source = "./"

  bucket_name = "my-app-user-uploads-production"
  environment = "production"
  application = "web-frontend"

  cors_rules = [
    {
      allowed_origins = ["https://app.example.com"]
      allowed_methods = ["GET", "PUT", "POST", "HEAD"]
      allowed_headers = ["*"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]
}
```

### 2. Ephemeral or Generated Files (Auto-expiring reports & exports)
For background jobs generating PDFs, CSVs, or temp files that should be cleaned up automatically after 30 days:

```hcl
module "reports_bucket" {
  source = "./"

  bucket_name     = "my-app-generated-reports"
  environment     = "production"
  expiration_days = 30
}
```

### 3. Application Logs & Long-Term Archival
For logs that should transition to Infrequent Access after 30 days, Glacier after 90 days, and expire after 365 days:

```hcl
module "app_logs" {
  source = "./"

  bucket_name                = "my-app-logs-production"
  environment                = "production"
  transition_to_ia_days      = 30
  transition_to_glacier_days = 90
  expiration_days            = 365
}
```

### 4. Custom KMS Encryption
To encrypt assets with an existing AWS KMS Customer Managed Key:

```hcl
module "secure_assets" {
  source = "./"

  bucket_name = "my-app-secure-assets"
  environment = "production"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/your-key-id"
}
```

---

## Connecting Your Application (IAM Permissions)

The module outputs ready-to-use IAM policy documents (`read_only_policy_json`, `read_write_policy_json`, `write_only_policy_json`) with correct ARN scopes (avoiding common `/*` mistakes).

Attach the policy directly to your ECS Task Role, Lambda Execution Role, or EC2 Instance Profile:

```hcl
resource "aws_iam_role_policy" "app_s3_access" {
  name   = "s3-access"
  role   = aws_iam_role.app_execution_role.id
  policy = module.app_assets.read_write_policy_json
}
```

---

## Design Decisions & Guardrails

| Decision | Default | Why? |
|---|---|---|
| **Public Access Block** | Enabled (all 4 flags) | Application assets must not be leaked via accidental public ACLs or open bucket policies. |
| **TLS Enforcement** | Enabled | Enforces HTTPS transport, rejecting unencrypted HTTP traffic. |
| **Object Ownership** | `BucketOwnerEnforced` | Modern AWS recommendation. Disables ACLs entirely and ensures the bucket owner owns all uploaded objects. |
| **Encryption at Rest** | `AES256` (SSE-S3) | Zero configuration encryption at rest. Optional `kms_key_arn` enables SSE-KMS. S3 Bucket Keys are enabled to slash KMS request costs. |
| **Versioning** | Enabled | Protects critical application data from accidental deletes or overwrite bugs. |
| **Multipart Cleanup** | 7 days | Abandoned multipart uploads silently consume storage and cost money forever. This guarantees cleanup. |
| **Version Lifecycle** | 30d IA / 90d Expire | Balances recovery of deleted/overwritten objects with cost predictability. |
| **Force Destroy** | `false` | Prevents catastrophic accidental data loss during infrastructure changes. Can be set to `true` in ephemeral test/dev. |

---

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `bucket_name` | `string` | **Required** | Globally unique name of the S3 bucket (3-63 chars, lowercase, hyphens). |
| `environment` | `string` | `"production"` | Deployment environment tag (`production`, `staging`, `dev`). |
| `application` | `string` | `null` | Application/service name tag. |
| `tags` | `map(string)` | `{}` | Additional custom tags. |
| `force_destroy` | `bool` | `false` | Allow deleting bucket even when non-empty (useful for test/dev). |
| `block_public_access` | `bool` | `true` | Block all public ACLs and bucket policies. |
| `enforce_tls` | `bool` | `true` | Deny unencrypted HTTP requests. |
| `object_ownership` | `string` | `"BucketOwnerEnforced"` | Ownership mode (`BucketOwnerEnforced`, `BucketOwnerPreferred`, `ObjectWriter`). |
| `custom_bucket_policy` | `string` | `null` | Additional bucket policy JSON to merge with standard policy. |
| `sse_algorithm` | `string` | `"AES256"` | Server-side encryption algorithm (`AES256` or `aws:kms`). |
| `kms_key_arn` | `string` | `null` | Customer Managed KMS Key ARN for SSE-KMS. |
| `bucket_key_enabled` | `bool` | `true` | Use S3 Bucket Keys to minimize KMS costs. |
| `versioning_enabled` | `bool` | `true` | Enable S3 versioning. |
| `enable_lifecycle_rules` | `bool` | `true` | Enable standard automated lifecycle management. |
| `abort_incomplete_multipart_upload_days` | `number` | `7` | Days to wait before aborting incomplete multipart uploads. |
| `noncurrent_version_transition_days` | `number` | `30` | Days before transitioning noncurrent versions to Standard-IA. |
| `noncurrent_version_expiration_days` | `number` | `90` | Days before deleting noncurrent versions. |
| `transition_to_intelligent_tiering_days` | `number` | `null` | Days before transitioning current objects to Intelligent-Tiering. |
| `transition_to_ia_days` | `number` | `null` | Days before transitioning current objects to Standard-IA. |
| `transition_to_glacier_days` | `number` | `null` | Days before transitioning current objects to Glacier. |
| `expiration_days` | `number` | `null` | Days before deleting current objects (for logs/temp files). |
| `cors_rules` | `list(object)` | `[]` | CORS configuration rules for browser uploads/access. |
| `logging_target_bucket` | `string` | `null` | Target bucket for S3 access logs. |
| `logging_target_prefix` | `string` | `null` | Prefix for access logs. Defaults to `s3-access-logs/<bucket_name>/`. |
| `create_iam_policies` | `bool` | `false` | Whether to provision AWS managed IAM policy resources. |

---

## Outputs

| Name | Description |
|---|---|
| `bucket_id` | Bucket name identifier. |
| `bucket_name` | Convenience alias for `bucket_id`. |
| `bucket_arn` | Bucket Amazon Resource Name (ARN). |
| `bucket_domain_name` | S3 domain name (`bucketname.s3.amazonaws.com`). |
| `bucket_regional_domain_name` | S3 regional domain name. |
| `bucket_region` | AWS region hosting the bucket. |
| `read_only_policy_json` | IAM policy document JSON for read-only access. |
| `read_write_policy_json` | IAM policy document JSON for full read/write access. |
| `write_only_policy_json` | IAM policy document JSON for write/ingest access. |
| `read_only_policy_arn` | ARN of created read-only IAM policy (if `create_iam_policies = true`). |
| `read_write_policy_arn` | ARN of created read-write IAM policy (if `create_iam_policies = true`). |
