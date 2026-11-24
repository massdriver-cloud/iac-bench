# Standard Application Asset S3 Bucket Module

This OpenTofu module creates a secure, standard AWS S3 bucket tailored for application assets such as user uploads, images, media, generated reports, and log files.

It enforces corporate best practices out of the box so application developers don't need deep S3 knowledge to get secure, compliant storage.

## Features & Secure Defaults

- **Public Access Block**: All public ACLs and bucket policies are blocked by default (`block_public_access = true`).
- **TLS/SSL Enforcement**: Rejects unencrypted (HTTP) transport via bucket policy (`enforce_ssl = true`).
- **Server-Side Encryption**: Enabled by default (`AES256` or `aws:kms` with optional CMK creation).
- **Modern Access Control**: Disables legacy S3 ACLs using `BucketOwnerEnforced` object ownership.
- **Data Protection**: Object versioning enabled by default (`versioning_enabled = true`).
- **Cost Protection Lifecycle Rules**: Automatically aborts incomplete multipart uploads after 7 days and cleans up old noncurrent object versions after 90 days.
- **CORS Support**: Optional browser cross-origin asset access and direct uploads.
- **Logging & Monitoring**: Support for server access logging and Amazon EventBridge integration.

---

## Quick Start Examples

### 1. Simple Application Bucket (Default Secure Setup)

```hcl
module "app_assets" {
  source      = "path/to/module"
  bucket_name = "my-company-user-uploads-prod"

  tags = {
    Environment = "production"
    Application = "user-service"
  }
}
```

### 2. Web Application with CORS Support (For Browser Uploads)

```hcl
module "frontend_assets" {
  source      = "path/to/module"
  bucket_name = "my-company-frontend-media"

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "PUT", "POST"]
      allowed_origins = ["https://app.example.com"]
      max_age_seconds = 3600
    }
  ]

  tags = {
    Environment = "production"
    Application = "frontend"
  }
}
```

### 3. KMS Encrypted Bucket with Custom IAM Policy

```hcl
module "sensitive_documents" {
  source         = "path/to/module"
  bucket_name    = "my-company-sensitive-docs"
  sse_algorithm  = "aws:kms"
  create_kms_key = true

  custom_policy_statements = [
    {
      sid     = "AllowAppRoleAccess"
      effect  = "Allow"
      actions = ["s3:GetObject", "s3:PutObject"]
      resources = [
        "arn:aws:s3:::my-company-sensitive-docs/*"
      ]
      principals = [
        {
          type        = "AWS"
          identifiers = ["arn:aws:iam::123456789012:role/doc-processor-role"]
        }
      ]
    }
  ]
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `bucket_name` | Name of the S3 bucket | `string` | n/a | yes |
| `tags` | Map of tags assigned to all resources | `map(string)` | `{}` | no |
| `force_destroy` | Allow deletion of bucket containing objects | `bool` | `false` | no |
| `block_public_access` | Block all public access | `bool` | `true` | no |
| `object_ownership` | S3 object ownership setting | `string` | `"BucketOwnerEnforced"` | no |
| `enforce_ssl` | Deny unencrypted (HTTP) access | `bool` | `true` | no |
| `sse_algorithm` | Encryption algorithm (`AES256` or `aws:kms`) | `string` | `"AES256"` | no |
| `kms_key_arn` | Existing KMS Key ARN for SSE-KMS | `string` | `null` | no |
| `create_kms_key` | Create dedicated KMS key for SSE-KMS | `bool` | `false` | no |
| `bucket_key_enabled` | Enable S3 Bucket Key for SSE-KMS | `bool` | `true` | no |
| `versioning_enabled` | Protect against accidental object loss | `bool` | `true` | no |
| `abort_incomplete_multipart_upload_days` | Days to clean up failed uploads | `number` | `7` | no |
| `noncurrent_version_expiration_days` | Days to delete noncurrent versions | `number` | `90` | no |
| `cors_rules` | CORS rules list for browser access | `list(object)` | `[]` | no |
| `logging_target_bucket` | S3 bucket for access logs | `string` | `null` | no |
| `enable_eventbridge` | Send S3 events to EventBridge | `bool` | `false` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Bucket name / ID |
| `bucket_arn` | Bucket ARN |
| `bucket_domain_name` | Bucket domain name |
| `bucket_regional_domain_name` | Bucket regional domain name |
| `bucket_hosted_zone_id` | Route 53 Hosted Zone ID |
| `bucket_region` | AWS region of the bucket |
| `kms_key_arn` | KMS key ARN used (if KMS enabled) |
| `kms_key_id` | KMS key ID (if created) |
