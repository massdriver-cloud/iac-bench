# Standard S3 bucket for application assets

This is the standard OpenTofu root module for provisioning an S3 bucket for an
application's assets: user uploads, images and videos, generated files, logs,
and similar object storage.

The module makes the security and lifecycle decisions for you, so app teams
only need to provide two inputs:

- `bucket_name` — a globally unique S3 bucket name
- `application` — the owning application/service name (used for tags and
  access-log prefixes)

## Quick start

Copy `minimal.tfvars`, change the two required values, and plan/apply:

```hcl
# minimal.tfvars
bucket_name = "myapp-assets-dev"
application = "myapp"
region      = "us-east-1"
```

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## What the module decides for you

- **Private by default**: all public access is blocked.
- **Object ACLs disabled**: access is controlled only through IAM policies and
  the bucket policy (`BucketOwnerEnforced`).
- **Versioning enabled**: overwrites and deletes are recoverable.
- **Encryption on by default**: SSE-S3 (AES256); opt into SSE-KMS with
  `encryption_algorithm = "aws:kms"` and, optionally, `kms_key_arn`.
- **HTTPS enforced**: a bucket policy denies non-TLS requests.
- **Lifecycle cleanup enabled**: incomplete multipart uploads are aborted after
  7 days and superseded (noncurrent) versions expire after 90 days.
- **Optional access grants**: pass IAM principal ARNs to
  `allowed_read_principals` and/or `allowed_write_principals` if an application
  role needs direct bucket-policy access. Most teams should grant access from
  the application's IAM role policies instead.
- **Optional access logging**: set `access_logging_target_bucket` to deliver
  server access logs to a separate bucket.

## Important inputs

| Name | Required | Default | Purpose |
| --- | --- | --- | --- |
| `bucket_name` | yes | — | Globally unique S3 bucket name |
| `application` | yes | — | Owning application/service name |
| `environment` | no | `dev` | Environment label used in tags |
| `region` | no | env region | AWS region for the bucket |
| `allowed_write_principals` | no | `[]` | IAM principal ARNs allowed to read/write |
| `allowed_read_principals` | no | `[]` | IAM principal ARNs allowed to read |
| `tags` | no | `{}` | Extra tags for the bucket |

See `variables.tf` for the full set of optional inputs and defaults.
