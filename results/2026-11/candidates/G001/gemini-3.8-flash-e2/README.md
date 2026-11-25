# Standard Application Assets S3 Bucket Module

A secure, cost-optimized, production-ready standard S3 bucket module designed specifically for application development teams.

Application teams frequently need S3 storage for assets — user uploads, images, video processing, temporary generated exports, and log archives. This module provides sensible, secure-by-default configurations so application developers don't have to be AWS S3 experts.

---

## Quick Start (Minimal Usage)

Application developers can get a fully compliant, secure S3 bucket with a single required input:

```hcl
module "app_assets" {
  source = "./"

  bucket_name = "my-app-assets-prod"
  environment = "production"
  application = "user-service"
}
```

---

## Design Decisions Handled For You

1. **Security by Default**:
   - **Public Access Blocked**: Strict S3 Public Access Block enabled across all four dimensions.
   - **Ownership Enforced**: ACLs disabled with `BucketOwnerEnforced`. Objects uploaded across accounts or via presigned URLs are automatically owned by the bucket owner.
   - **Encryption at Rest**: SSE-S3 (`AES256`) enabled out-of-the-box at zero additional cost, with optional SSE-KMS support.
   - **In-Transit Security**: Plaintext HTTP access is blocked; TLS 1.2+ is strictly enforced via bucket policy.
   - **Accidental Deletion Protection**: `force_destroy` defaults to `false` to safeguard production assets against accidental infrastructure teardown.

2. **Cost Optimization & Lifecycle Management**:
   - **Incomplete Multipart Uploads**: Aborted automatically after 7 days, eliminating hidden charges from failed large file uploads.
   - **Versioning & Retention**: Versioning is enabled to protect against accidental overwrites. Older versions transition to Standard-IA at 30 days and expire at 90 days, retaining the latest 3 noncurrent versions.
   - **Expired Delete Marker Cleanup**: Automatically removes expired delete markers when all versions are deleted.

3. **Application Developer IAM Helpers**:
   - Ready-to-use least-privilege IAM policy documents are automatically exported as JSON (`read_only_policy_json`, `read_write_policy_json`, `write_only_policy_json`).
   - If KMS is configured, the IAM policy documents automatically include the necessary `kms:Decrypt` and `kms:GenerateDataKey` permissions.

---

## Common Use Cases

### 1. Web Application with Direct Browser Uploads (CORS)

When frontends upload images/documents directly to S3 using presigned URLs:

```hcl
module "web_assets" {
  source = "./"

  bucket_name = "frontend-uploads-prod"
  environment = "production"
  application = "web-portal"

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["https://app.example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]
}
```

### 2. Event-Driven Asset Processing (Thumbnails, Transcoding)

Integrate directly with Amazon EventBridge to trigger Lambdas or ECS workers whenever users upload media:

```hcl
module "media_bucket" {
  source = "./"

  bucket_name        = "user-media-prod"
  environment        = "production"
  application        = "media-service"
  enable_eventbridge = true
}
```

### 3. Ephemeral / Temporary Files & Application Logs

For temporary reports, exports, or application logs that should auto-expire after 30 days:

```hcl
module "temp_exports" {
  source = "./"

  bucket_name                    = "report-exports-staging"
  environment                    = "staging"
  current_version_expiration_days = 30
  versioning_enabled             = false
}
```

### 4. Enterprise Compliance with Customer-Managed KMS Key

```hcl
module "secure_documents" {
  source = "./"

  bucket_name = "confidential-documents-prod"
  environment = "production"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/your-key-uuid"
}
```

### 5. Connecting Your Compute (ECS / Lambda / EKS)

Use the module's generated IAM policy outputs directly in your application's IAM role:

```hcl
resource "aws_iam_role_policy" "app_s3_access" {
  name   = "s3-asset-access"
  role   = aws_iam_role.app_task_role.id
  policy = module.app_assets.read_write_policy_json
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `bucket_name` | Name of the bucket (3-63 chars, lowercase alphanumeric and hyphens). | `string` | n/a | yes |
| `environment` | Deployment environment (`production`, `staging`, `dev`). | `string` | `null` | no |
| `application` | Name of the owning service or application. | `string` | `null` | no |
| `tags` | Additional tags to merge with standard tags. | `map(string)` | `{}` | no |
| `force_destroy` | Allow OpenTofu to destroy bucket even if non-empty. | `bool` | `false` | no |
| `block_public_access` | Block all public access via Public Access Block. | `bool` | `true` | no |
| `object_ownership` | S3 Object Ownership (`BucketOwnerEnforced`). | `string` | `"BucketOwnerEnforced"` | no |
| `enforce_tls` | Deny plaintext HTTP requests via bucket policy. | `bool` | `true` | no |
| `min_tls_version` | Minimum TLS version allowed. | `string` | `"1.2"` | no |
| `kms_key_arn` | KMS Key ARN for SSE-KMS. If null, AES256 is used. | `string` | `null` | no |
| `bucket_key_enabled` | Enable S3 Bucket Key to minimize KMS API costs. | `bool` | `true` | no |
| `custom_bucket_policy` | Additional JSON policy statements to merge into bucket policy. | `string` | `null` | no |
| `versioning_enabled` | Enable versioning to protect assets against accidental overwrites. | `bool` | `true` | no |
| `lifecycle_rules_enabled` | Enable automated lifecycle management. | `bool` | `true` | no |
| `abort_incomplete_multipart_upload_days` | Days before incomplete multipart uploads are aborted. | `number` | `7` | no |
| `clean_expired_delete_markers` | Clean up expired object delete markers automatically. | `bool` | `true` | no |
| `noncurrent_version_transition_days` | Days before noncurrent versions transition to Standard-IA. | `number` | `30` | no |
| `noncurrent_version_expiration_days` | Days before noncurrent versions are deleted. | `number` | `90` | no |
| `noncurrent_version_retain_count` | Number of newer noncurrent versions to preserve. | `number` | `3` | no |
| `current_version_transition_ia_days` | Days before current versions transition to Standard-IA. | `number` | `null` | no |
| `current_version_transition_glacier_days` | Days before current versions transition to Glacier. | `number` | `null` | no |
| `current_version_expiration_days` | Days before current objects expire. | `number` | `null` | no |
| `custom_lifecycle_rules` | Custom lifecycle rules for prefix-specific retention. | `any` | `[]` | no |
| `cors_rules` | CORS rules for web frontend uploads/fetches. | `list(object)` | `[]` | no |
| `logging_target_bucket` | Target bucket for S3 server access logging. | `string` | `null` | no |
| `logging_target_prefix` | Prefix for server access logs. | `string` | `null` | no |
| `enable_eventbridge` | Send S3 events to Amazon EventBridge. | `bool` | `false` | no |
| `create_iam_access_policies` | Create managed IAM policy resources in AWS. | `bool` | `false` | no |
| `iam_policy_name_prefix` | Prefix for managed IAM policies. | `string` | `null` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Name / ID of the S3 bucket. |
| `bucket_name` | Name of the S3 bucket. |
| `bucket_arn` | ARN of the S3 bucket. |
| `bucket_domain_name` | S3 bucket domain name. |
| `bucket_regional_domain_name` | Regional bucket domain name. |
| `hosted_zone_id` | Route 53 Hosted Zone ID for bucket's region. |
| `versioning_enabled` | Whether versioning is active. |
| `encryption_algorithm` | Server-side encryption algorithm (`AES256` or `aws:kms`). |
| `kms_key_arn` | KMS key ARN configured (if any). |
| `read_only_policy_json` | IAM policy JSON document granting read-only access. |
| `read_write_policy_json` | IAM policy JSON document granting read/write access. |
| `write_only_policy_json` | IAM policy JSON document granting write/upload-only access. |
| `read_only_policy_arn` | ARN of managed read-only IAM policy (if created). |
| `read_write_policy_arn` | ARN of managed read-write IAM policy (if created). |
| `write_only_policy_arn` | ARN of managed write-only IAM policy (if created). |
