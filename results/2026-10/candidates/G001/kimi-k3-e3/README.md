# Standard application asset bucket

The one sanctioned way for an application team to get an S3 bucket for the
assets its app stores and works with: user uploads, images and video,
generated files, logs.

It is built for app developers who are not S3 experts: pick a name, set some
tags, ship it. Everything else is decided for you, in line with the platform
team's standards — and most of it is deliberately not configurable.

## Usage

```hcl
module "app_assets" {
  source = "<where the platform team publishes this module>"

  name = "acme-billing-web-prod-assets"

  tags = {
    team = "billing"
    app  = "billing-web"
    env  = "prod"
  }
}
```

Then wire your app to it:

```hcl
resource "aws_iam_role_policy" "app" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [module.app_assets.bucket_arn, "${module.app_assets.bucket_arn}/*"]
    }]
  })
}
```

## What the module decides for you

| Decision | Default | Why |
| --- | --- | --- |
| Public access | Fully blocked. **Not configurable.** | App assets must never be reachable by the public internet. Serve public content through a CDN instead. |
| Transport | TLS only — the bucket policy denies every plaintext request. | Encryption in transit is not optional. |
| Encryption at rest | SSE-S3 (AES256). Bring a KMS key via `kms_key_arn` only if you have a concrete reason. | SSE-S3 is free, automatic, and needs no key management. |
| ACLs | Disabled (bucket-owner-enforced object ownership). | One access model (IAM/bucket policies) instead of two confusing ones. |
| Versioning | On; old versions are expired after 90 days (`versioning_enabled`, `noncurrent_version_expiration_days`). | Undo window for accidental deletes/overwrites, with bounded cost. |
| Incomplete multipart uploads | Aborted after 7 days (`abort_incomplete_multipart_upload_days`). | They are invisible and cost money forever otherwise. |
| Object expiry | Off (`object_expiration_days`). Set it only for disposable content like logs. | Deleting user data by default would be a terrible surprise. |
| Access logging | Off. Opt in with `access_logging` pointing at a log bucket. | Only some teams need a request audit trail. |
| CORS | None. Opt in with `cors_rules` for direct browser uploads. | Browsers shouldn't talk to the bucket cross-origin unless the app design calls for it. |
| Deletion protection | `force_destroy = false`. | `tofu destroy` must not silently empty a bucket of user data. |

## Inputs

See `variables.tf`. Only `name` is required; every other input has a default
the module stands behind.

## Outputs

| Output | Use it for |
| --- | --- |
| `bucket_name` | Telling your application which bucket to use. |
| `bucket_arn` | IAM policies granting your app access. |
| `bucket_region` | S3 clients that need an explicit region. |
| `bucket_regional_domain_name` | Object URLs / CDN origins. |
