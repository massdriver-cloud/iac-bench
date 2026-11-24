# app-assets-bucket

The standard way to get an S3 bucket for your application's assets (uploads,
images, videos, generated files, logs). Give it a name; the module takes care
of the rest.

## What you get, without asking

| Concern | Decision |
|---|---|
| Public access | Fully blocked. ACLs disabled; access is IAM + bucket policy only. |
| Encryption | Always on. SSE-S3 by default; SSE-KMS if you pass `kms_key_arn`. |
| Transport | Non-TLS and TLS < 1.2 requests are denied by bucket policy. |
| Accidental deletes/overwrites | Versioning on; previous versions kept 30 days then purged. |
| Cost hygiene | Abandoned multipart uploads removed after 7 days; objects move to Intelligent-Tiering after 30 days. |
| Destroy safety | `tofu destroy` refuses to delete a non-empty bucket unless `force_destroy = true`. |

## Examples

Minimal — a bucket for user uploads:

```hcl
module "uploads" {
  source = "<path or git url to this module>"

  name = "acme-photos-uploads-prod"
  tags = { Application = "photos", Team = "media", Environment = "prod" }
}
```

Browser uploads via pre-signed URLs (needs CORS):

```hcl
module "uploads" {
  source = "<path or git url to this module>"

  name                 = "acme-photos-uploads-prod"
  cors_allowed_origins = ["https://photos.example.com"]
}
```

Logs or temporary files that should disappear on their own:

```hcl
module "exports" {
  source = "<path or git url to this module>"

  name            = "acme-reports-exports-prod"
  expiration_days = 14
}
```

## Giving your application access

The module deliberately does **not** create IAM roles; attach a policy to your
application's existing role using the outputs:

```hcl
data "aws_iam_policy_document" "app_bucket" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.uploads.bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [module.uploads.bucket_objects_arn]
  }
}
```

## Inputs

| Name | Required | Default | Purpose |
|---|---|---|---|
| `name` | yes | – | Globally unique bucket name |
| `tags` | no | `{}` | Extra tags |
| `cors_allowed_origins` | no | `[]` | Browser origins allowed to call the bucket directly |
| `expiration_days` | no | `null` | Auto-delete objects after N days |
| `kms_key_arn` | no | `null` | Use a customer-managed KMS key |
| `versioning_enabled` | no | `true` | Keep previous object versions |
| `noncurrent_version_retention_days` | no | `30` | How long to keep previous versions |
| `intelligent_tiering_after_days` | no | `30` | When to move objects to Intelligent-Tiering (`null` = never) |
| `access_log_bucket` | no | `null` | Deliver server access logs to this bucket |
| `access_log_prefix` | no | `"<name>/"` | Prefix for access logs |
| `force_destroy` | no | `false` | Allow destroying a non-empty bucket |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_objects_arn`, `bucket_regional_domain_name`, `region`, `kms_key_arn`.
