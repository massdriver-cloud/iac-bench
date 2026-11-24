# Standard Application Assets S3 Bucket

This module creates an S3 bucket with the security and lifecycle defaults that
application asset storage should have, so app teams do not have to reason about
S3 configuration themselves.

## What it configures

- A unique bucket name derived from `name` and `environment`, so two teams or
  two environments do not accidentally collide.
- Server-side encryption with S3-managed keys (SSE-S3 / AES256) for every object.
- Object versioning, so accidental overwrites and deletes can be recovered.
- A lifecycle rule that aborts incomplete multipart uploads after 7 days and
  removes non-current versions after 90 days by default.
- All public access blocked (`BucketOwnerEnforced` ownership plus a public access
  block), making the bucket private by default.

## Minimal usage

Create a `minimal.tfvars` (or pass these directly):

```hcl
name        = "myapp"
environment = "dev"
```

Then plan and apply:

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

When used as a module by an application stack:

```hcl
module "assets" {
  source = "git::https://example.com/terraform/app-assets-bucket.git"

  name        = "myapp"
  environment = "dev"
}

output "assets_bucket" {
  value = module.assets.bucket_name
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `name` | Lowercase application or service name used in the bucket name prefix. | `string` | required |
| `environment` | Environment name, for example `dev`, `staging`, or `prod`. | `string` | required |
| `region` | AWS region for the bucket. | `string` | `"us-east-1"` |
| `versioning_enabled` | Keep multiple versions of objects. | `bool` | `true` |
| `force_destroy` | Allow non-empty bucket deletion. | `bool` | `false` |
| `tags` | Additional tags. | `map(string)` | `{}` |
| `noncurrent_version_expiration_days` | Delete non-current versions after this many days; `0` keeps them indefinitely. | `number` | `90` |
| `abort_incomplete_multipart_upload_days` | Abort incomplete multipart uploads after this many days; `0` disables the rule. | `number` | `7` |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Generated S3 bucket name. |
| `bucket_arn` | S3 bucket ARN. |
| `bucket_id` | S3 bucket ID. |
| `bucket_regional_domain_name` | Regional domain name of the bucket. |
