# App assets bucket

The standard way to get an S3 bucket for your application's files (uploads, images, videos, generated files, logs).

## Usage

```hcl
app_name    = "photo-service"
environment = "dev"
```

That's it. Then attach the `read_write_policy_json` output to your app's IAM role, and give the app the `bucket_name` output.

## What you get (no configuration needed)

- Unique bucket name: `<app>-<env>-<purpose>-<random suffix>`
- Never public: all public access blocked, ACLs disabled (bucket owner owns all objects). Share files through presigned URLs or CloudFront.
- Encrypted at rest (SSE-S3, or your KMS key via `kms_key_arn`) and in transit (HTTPS / TLS 1.2+ enforced).
- Versioning: overwritten or deleted files can be recovered for 30 days (`noncurrent_version_retention_days`).
- Cost housekeeping: incomplete uploads cleaned up after 7 days, objects ≥128 KB move to Intelligent-Tiering automatically.
- Protected from accidental deletion (`force_destroy = false`).

## Optional knobs

| Input | When to use |
|---|---|
| `purpose` | You need more than one bucket for the app (e.g. `uploads`, `logs`). |
| `cors_allowed_origins` | Browsers upload/download directly via presigned URLs. |
| `expire_objects_after_days` | Files are temporary (logs, exports). |
| `kms_key_arn` | Compliance requires a customer-managed key. |
| `access_log_bucket` | You must audit access to the bucket. |
| `tags`, `region`, `force_destroy` | Self-explanatory. |
