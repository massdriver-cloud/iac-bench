# Standard application asset bucket

This root module creates a private S3 bucket for application-owned assets. Application teams provide only an application and environment; S3 generates a globally unique bucket name. Use the `bucket_name` output (or an exact `bucket_name` input when a fixed name is required) to configure the application.

## Minimal use

```hcl
module "assets" {
  source = "./path/to/this/module"

  application = "photo-service"
  environment = "prod"
}
```

The included `minimal.tfvars` is the smallest complete instantiation for using this directory directly as a root module:

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Decisions made for every bucket

- Public access is blocked at the bucket level, including public policies and ACLs.
- ACLs are disabled with `BucketOwnerEnforced`; access is controlled with IAM and bucket policy.
- All bucket traffic must use TLS. No application or anonymous identities are granted access by the module.
- Objects are encrypted with S3-managed keys (SSE-S3/AES256), with no KMS charges. An existing KMS key can instead be supplied with `kms_key_arn`; its key policy remains the caller's responsibility.
- Versioning is enabled to protect against accidental overwrites and deletion. Noncurrent versions and expired delete markers are removed after 90 days; current application objects are **never** expired by the module.
- Incomplete multipart uploads are aborted after 7 days.
- Server access logs go to a separate private, encrypted bucket and expire after 90 days. Log delivery is authorized only for the source bucket and account. Set `access_logging_enabled = false` only when centralized logging is handled elsewhere.
- No CORS access is configured by default. Browser-based workflows can supply narrowly scoped `cors_rules`.
- Destruction refuses to delete a non-empty bucket by default. `force_destroy` is available for disposable environments and also applies to the log bucket.

The defaults favor data recovery and auditability, but retention periods and versioning can be changed deliberately through variables. Storage-class transitions are intentionally not imposed: access patterns and retrieval-cost tradeoffs differ between uploads, media, generated files, and logs.

## Browser upload example

```hcl
module "assets" {
  source      = "./path/to/this/module"
  application = "photo-service"
  environment = "prod"

  cors_rules = [{
    id              = "browser-upload"
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = ["https://photos.example.com"]
    allowed_headers = ["content-type", "x-amz-*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }]

  tags = {
    CostCenter = "photos"
  }
}
```

CORS is not authentication. Applications still need narrowly scoped IAM credentials or a controlled upload flow. This module does not create an application role because the required principals and object-prefix permissions are application-specific.

## Outputs

- `bucket_name`, `bucket_arn`, and `bucket_regional_domain_name` describe the asset bucket.
- `access_log_bucket_name` and `access_log_bucket_arn` describe the companion log bucket, or return `null` if logging is disabled.
