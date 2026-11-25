# Standard Application Asset S3 Bucket Module

A secure, batteries-included OpenTofu module designed for application engineering teams.

Application developers frequently hand-roll S3 buckets for application assets—user uploads, media files, generated exports, and logs. This often leads to misconfigurations: unblocked public access, missing encryption, lack of TLS enforcement, runaway storage costs from abandoned multipart uploads, and ACL permission mismatches.

This module provides sensible, production-ready defaults so developers can supply **a couple of obvious inputs** and trust the module's judgment for everything else.

---

## Key Defaults & Design Decisions

- **Private by Default**: All 4 S3 Block Public Access controls (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) are enabled.
- **Modern Ownership (No ACLs)**: `object_ownership` is set to `BucketOwnerEnforced`. Legacy S3 ACLs are disabled, ensuring the bucket owner owns all uploaded objects.
- **Encryption at Rest**: Server-side encryption is automatically enabled using AES-256 (`SSE-S3`) by default, with S3 Bucket Keys enabled. Custom KMS keys (`SSE-KMS`) are supported via `kms_key_arn`.
- **Enforced In-Transit Security**: An S3 bucket policy is automatically attached to deny all plaintext HTTP traffic (`aws:SecureTransport: false`) and reject connections below TLS 1.2.
- **Versioning Enabled**: Enabled by default to protect against accidental file deletions or overwrites.
- **Storage Cost Protection**:
  - **Incomplete Multipart Uploads**: Automatically aborted after 7 days. Prevents hidden runaway storage bills from interrupted uploads (common with video/large file uploads).
  - **Noncurrent Version Expiration**: Retains previous versions for 90 days before permanent deletion, preventing unlimited storage growth.
  - **Expired Delete Marker Cleanup**: Automatically removes expired delete markers when all non-current versions are gone.
- **Simple CORS Configuration**: Web and mobile applications uploading directly to S3 can simply specify `cors_allowed_origins = ["https://app.example.com"]`.

---

## Quickstart Examples

### 1. Minimal (User Uploads)
The simplest usage for application user uploads (avatars, attachments):

```hcl
module "user_uploads_bucket" {
  source = "./"

  bucket_name = "mycompany-user-uploads-production"
  environment = "production"
  application = "user-service"
}
```

### 2. Images and Videos with Browser Uploads (CORS & CloudFront)
For rich media files where frontends upload directly via presigned URLs and serve via CloudFront:

```hcl
module "media_assets" {
  source = "./"

  bucket_name = "mycompany-media-production"
  environment = "production"
  application = "media-api"

  # Allow web frontend direct uploads
  cors_allowed_origins = ["https://app.mycompany.com"]

  # Grant CloudFront Origin Access Control (OAC) read access
  cloudfront_distribution_arns = [
    "arn:aws:cloudfront::123456789012:distribution/EDFDVBD632BHXS"
  ]

  # Grant the backend application role read/write access
  read_write_principals = [
    "arn:aws:iam::123456789012:role/media-service-task-role"
  ]
}
```

### 3. Generated Files (Exports & Invoices)
For generated reports, PDF exports, or invoices that should automatically expire after 30 days:

```hcl
module "reports_bucket" {
  source = "./"

  bucket_name = "mycompany-generated-reports-production"
  environment = "production"
  application = "reporting-worker"

  # Automatically delete files after 30 days
  expiration_days = 30

  # Retain old versions for 7 days if replaced
  noncurrent_version_expiration_days = 7
}
```

### 4. Application Logs
For application log archives with 365-day retention and KMS customer-managed encryption:

```hcl
module "app_logs" {
  source = "./"

  bucket_name = "mycompany-app-logs-production"
  environment = "production"
  application = "audit-pipeline"

  expiration_days = 365
  kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/your-kms-key-id"

  read_write_principals = [
    "arn:aws:iam::123456789012:role/log-shipper-role"
  ]
}
```

---

## Requirements

| Name | Version |
|------|---------|
| opentofu / terraform | >= 1.6.0 |
| aws provider | >= 5.0 |

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `bucket_name` | Globally unique name for the S3 bucket | `string` | n/a | yes |
| `bucket` | Optional alias for bucket_name | `string` | `null` | no |
| `environment` | Deployment environment (`production`, `staging`, `dev`) | `string` | `"production"` | no |
| `application` | Name of the owning application/service | `string` | `null` | no |
| `tags` | Additional tags to merge onto resources | `map(string)` | `{}` | no |
| `force_destroy` | Allow deletion of non-empty bucket on destroy | `bool` | `false` | no |
| `versioning_enabled` | Enable object versioning | `bool` | `true` | no |
| `kms_key_arn` | KMS key ARN for SSE-KMS encryption (uses SSE-S3 AES256 if null) | `string` | `null` | no |
| `bucket_key_enabled` | Enable S3 Bucket Keys to reduce KMS costs | `bool` | `true` | no |
| `block_public_access` | Enable all 4 S3 public access blocks | `bool` | `true` | no |
| `object_ownership` | S3 Object Ownership rule | `string` | `"BucketOwnerEnforced"` | no |
| `enforce_tls` | Enforce HTTPS/TLS via bucket policy | `bool` | `true` | no |
| `minimum_tls_version` | Minimum TLS version required | `string` | `"1.2"` | no |
| `abort_incomplete_multipart_upload_days` | Days before incomplete multipart uploads are aborted | `number` | `7` | no |
| `noncurrent_version_expiration_days` | Days before non-current versions expire | `number` | `90` | no |
| `noncurrent_version_transition_days` | Days before non-current versions transition storage class | `number` | `null` | no |
| `noncurrent_version_transition_storage_class` | Storage class for non-current transitions | `string` | `"STANDARD_IA"` | no |
| `clean_expired_object_delete_markers` | Clean up expired object delete markers | `bool` | `true` | no |
| `expiration_days` | Days before current objects expire (useful for logs/temp files) | `number` | `null` | no |
| `transition_days` | Days before current objects transition storage class | `number` | `null` | no |
| `transition_storage_class` | Storage class for current object transitions | `string` | `"STANDARD_IA"` | no |
| `enable_intelligent_tiering` | Enable S3 Intelligent-Tiering archive tiers | `bool` | `false` | no |
| `cors_allowed_origins` | List of allowed CORS origins | `list(string)` | `[]` | no |
| `cors_allowed_methods` | List of allowed CORS HTTP methods | `list(string)` | `["GET", "HEAD", "PUT", "POST", "DELETE"]` | no |
| `cors_allowed_headers` | List of allowed CORS HTTP headers | `list(string)` | `["*"]` | no |
| `cors_expose_headers` | List of exposed CORS response headers | `list(string)` | `["ETag"]` | no |
| `cors_max_age_seconds` | Seconds browsers can cache CORS preflight responses | `number` | `3600` | no |
| `cors_rules` | Advanced: custom CORS rules | `any` | `[]` | no |
| `custom_lifecycle_rules` | Advanced: custom lifecycle rules | `any` | `[]` | no |
| `logging_target_bucket` | S3 bucket for access logs | `string` | `null` | no |
| `logging_target_prefix` | Prefix for access logs | `string` | `null` | no |
| `read_only_principals` | IAM ARNs granted read-only access via bucket policy | `list(string)` | `[]` | no |
| `read_write_principals` | IAM ARNs granted read-write access via bucket policy | `list(string)` | `[]` | no |
| `cloudfront_distribution_arns` | CloudFront distribution ARNs for OAC read access | `list(string)` | `[]` | no |
| `custom_policy_json` | Raw IAM policy JSON to merge with bucket policy | `string` | `null` | no |
| `custom_policy_documents` | List of IAM policy JSON documents to merge | `list(string)` | `[]` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | The S3 bucket name/ID |
| `bucket_name` | The S3 bucket name |
| `bucket_arn` | The ARN of the bucket |
| `bucket_domain_name` | Bucket domain name (`<name>.s3.amazonaws.com`) |
| `bucket_regional_domain_name` | Regional domain name (`<name>.s3.<region>.amazonaws.com`) |
| `bucket_region` | AWS region the bucket resides in |
| `hosted_zone_id` | Route 53 Hosted Zone ID for this bucket's region |
| `versioning_enabled` | Whether versioning is enabled on the bucket |
| `policy_json` | Complete IAM bucket policy JSON applied to the bucket |
