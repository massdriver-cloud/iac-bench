# Standard Application S3 Bucket Module

This OpenTofu module provides a secure, standard S3 bucket tailored for application teams storing application assets (user uploads, images, videos, generated files, logs).

## Features & Defaults
- **Block Public Access**: Public access is completely blocked by default (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`).
- **Enforce TLS/HTTPS**: S3 Bucket Policy automatically enforces TLS for all requests (`aws:SecureTransport = false` deny statement).
- **Default SSE Encryption**: AES256 server-side encryption enabled out-of-the-box, with support for KMS keys.
- **Object Ownership**: Set to `BucketOwnerEnforced` by default (disables legacy ACLs).
- **Versioning**: Enabled by default to protect against accidental object overwrites and deletions.
- **Automatic Lifecycle Rules**:
  - Automatically aborts incomplete multipart uploads after 7 days to clean up partial uploads.
  - Automatically expires noncurrent object versions after 90 days to manage storage costs.
  - Supports custom lifecycle rules (transitions to IA/Glacier, expiration).
- **CORS Support**: Configurable CORS rules for direct client browser uploads/downloads.
- **Logging Support**: Optional S3 server access logging.

## Usage

### Minimal Example
```hcl
module "app_assets_bucket" {
  source      = "./"
  bucket_name = "my-app-assets-bucket"
}
```

### Complete Example
```hcl
module "app_assets_bucket" {
  source      = "./"
  bucket_name = "my-app-assets-bucket"

  versioning_enabled = true
  force_destroy      = false

  tags = {
    Environment = "production"
    Application = "media-service"
  }

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "PUT", "POST"]
      allowed_origins = ["https://app.example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]
}
```
