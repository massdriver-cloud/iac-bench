# Standard Application S3 Bucket Module

This OpenTofu module creates a secure, standard AWS S3 bucket designed for application asset storage (e.g. user uploads, media, generated files, logs).

## Features & Defaults
- **Public Access Blocked**: Enabled by default (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`).
- **Encryption at Rest**: Default `AES256` (SSE-S3), configurable to use customer-managed AWS KMS keys (`aws:kms`).
- **TLS/HTTPS Enforcement**: Bucket policy automatically denies non-TLS (`aws:SecureTransport = false`) requests.
- **Versioning**: Enabled by default to protect against accidental object deletion or overwriting.
- **Ownership Controls**: `BucketOwnerEnforced` by default to disable legacy ACLs and enforce bucket owner permissions.
- **Lifecycle Rules**: Automatically aborts incomplete multipart uploads after 7 days and cleans up noncurrent version history after 90 days (configurable).
- **CORS Support**: Easily configured for direct web client uploads or downloads.

## Usage Example

```hcl
module "app_assets_bucket" {
  source      = "./"
  bucket_name = "my-company-app-assets-prod"

  tags = {
    Environment = "production"
    Application = "asset-service"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `bucket_name` | Name of the S3 bucket (must be globally unique) | `string` | n/a | yes |
| `region` | AWS region where resources will be created | `string` | `"us-east-1"` | no |
| `versioning_enabled` | Enable bucket versioning | `bool` | `true` | no |
| `block_public_access` | Block public access settings | `bool` | `true` | no |
| `enable_tls_only_policy` | Enforce HTTPS (TLS) for all requests | `bool` | `true` | no |
| `kms_key_arn` | KMS key ARN for SSE-KMS encryption | `string` | `null` | no |
| `bucket_key_enabled` | Enable S3 Bucket Keys when using SSE-KMS | `bool` | `true` | no |
| `object_ownership` | Object ownership rule (`BucketOwnerEnforced`, `BucketOwnerPreferred`, `ObjectWriter`) | `string` | `"BucketOwnerEnforced"` | no |
| `abort_incomplete_multipart_upload_days` | Days to wait before aborting incomplete multipart uploads | `number` | `7` | no |
| `noncurrent_version_expiration_days` | Days after which noncurrent versions expire | `number` | `90` | no |
| `cors_rules` | List of CORS configuration rules | `list(object)` | `[]` | no |
| `logging` | Target bucket and prefix for access logging | `object` | `null` | no |
| `custom_policy_document_json` | Optional IAM policy document to merge into bucket policy | `string` | `null` | no |
| `custom_lifecycle_rules` | Additional lifecycle management rules | `list(object)` | `[]` | no |
| `force_destroy` | Allow bucket deletion even if non-empty | `bool` | `false` | no |
| `tags` | Map of tags to assign to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Name / ID of the created S3 bucket |
| `bucket_arn` | ARN of the created S3 bucket |
| `bucket_domain_name` | Domain name of the bucket |
| `bucket_regional_domain_name` | Regional domain name of the bucket |
| `bucket_hosted_zone_id` | Route 53 Hosted Zone ID for the bucket's region |
| `bucket_region` | AWS Region of the bucket |
