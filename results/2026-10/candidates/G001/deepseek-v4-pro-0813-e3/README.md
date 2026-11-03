# Standard application-assets S3 bucket

This module is the standard way an application team gets an S3 bucket for the
assets its application stores: user uploads, images, videos, generated files,
and logs.

App developers should only need to supply two values: `application` and
`environment`. Everything else is decided by the module.

## Usage

Copy `minimal.tfvars`, change the two values, and plan/apply:

```hcl
application = "checkout"
environment = "staging"
```

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Decisions the module makes for you

- **Unique bucket name** — generated from `application` and `environment`, with
  a random suffix so S3's global namespace collision rules are handled.
- **Private by default** — all public access is blocked.
- **ACLs disabled** — bucket ownership is enforced so objects are owned by the
  bucket account and access is managed only through IAM/bucket policies.
- **HTTPS required** — a bucket policy denies any request made over plain HTTP.
- **Encryption at rest** — all objects are encrypted with S3-managed keys
  (SSE-S3 / AES256), so no KMS key management is required.
- **Versioning enabled** — accidental overwrites and deletions can be recovered.
- **Lifecycle hygiene** — incomplete multipart uploads are aborted after 7 days,
  and noncurrent versions are expired after 90 days by default.

## Optional inputs

| Name | Default | Purpose |
| --- | --- | --- |
| `bucket_name` | `null` | Use an explicit bucket name instead of a generated one. |
| `force_destroy` | `false` | Allow bucket deletion even when objects remain. |
| `versioning_enabled` | `true` | Toggle object versioning. |
| `noncurrent_version_expiration_days` | `90` | Expire old versions after N days (`null` keeps them forever). |
| `abort_incomplete_multipart_upload_days` | `7` | Abort incomplete multipart uploads after N days. |
| `tags` | `{}` | Extra tags to apply. |
