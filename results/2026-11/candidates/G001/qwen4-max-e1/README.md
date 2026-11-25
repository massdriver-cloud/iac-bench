# Standard application asset bucket

The standard way for an application team to get an S3 bucket for its assets
(user uploads, images/video, generated files, logs). You supply an
application name and an environment; the module owns every other decision.

## Usage

```hcl
module "assets" {
  source = "git::https://example.com/infra/tofu-s3-assets.git" # or a local path

  application = "storefront"
  environment = "prod"

  tags = {
    Team        = "checkout"
    CostCenter  = "cc-1234"
  }
}
```

Then point your app at `module.assets.bucket_name` (or `s3_uri`) and grant its
IAM role access to `module.assets.bucket_arn` and `"<arn>/*"`.

Minimal instantiation (see `minimal.tfvars`):

```hcl
application = "example-app"
environment = "dev"
```

## What you get, automatically

| Concern | Decision |
| --- | --- |
| Naming | `<application>-<environment>-assets-<account-id>` — deterministic, globally unique, DNS/TLS-safe |
| Public access | Impossible via this module: all four public-access blocks on, ACLs disabled (`BucketOwnerEnforced`) |
| Encryption at rest | Always on. SSE-S3 (AES256) by default; SSE-KMS + Bucket Keys if you pass `kms_key_arn` |
| Transport security | Bucket policy denies all non-TLS requests |
| Recoverability | Versioning always on; noncurrent versions expire after 30 days (tunable, min 7) |
| Cost hygiene | Incomplete multipart uploads aborted after 7 days |
| Deletion safety | `force_destroy = false`; a stray destroy cannot wipe a non-empty bucket |
| Tagging | `Name`, `Application`, `Environment`, `ManagedBy=opentofu` always set; your `tags` merged in |

## Inputs

Required: `application`, `environment` (`dev` | `test` | `staging` | `prod`).

Optional (most teams never set these):

- `aws_region` (default `us-east-1`)
- `tags` (default `{}`; module-managed keys cannot be overridden)
- `kms_key_arn` (default `null` → SSE-S3; if set, your app role needs
  `kms:Decrypt` / `kms:GenerateDataKey` on the key)
- `noncurrent_version_expiration_days` (default `30`, minimum `7`)
- `force_destroy` (default `false`; only for throwaway dev buckets)

## Outputs

`bucket_name`, `bucket_arn`, `bucket_regional_domain_name`,
`bucket_domain_name`, `s3_uri`, `aws_region`, `kms_key_arn`.

## Notes for app developers

- Uploads need **no** special headers: default encryption applies to every
  object automatically. Do not set ACLs — they are disabled.
- Use HTTPS endpoints only (HTTP is denied by policy). Prefer
  `bucket_regional_domain_name` when configuring SDK endpoints.
- Deleting or overwriting an object is recoverable for
  `noncurrent_version_expiration_days` days via S3 versioning.
- Serving assets publicly (e.g. a website) is deliberately out of scope:
  front the bucket with CloudFront + Origin Access Control instead.
