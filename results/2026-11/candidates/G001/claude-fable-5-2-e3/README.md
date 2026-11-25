# Application assets bucket

The standard way for an application team to get an S3 bucket for the things
their application stores: user uploads, images and videos, generated files,
logs. You say which application and environment it is for; the module makes
every other decision.

## Quick start

```hcl
module "assets" {
  source = "./path/to/this/module"

  application = "photo-service"
  environment = "prod"
}

# Let your application use the bucket: attach the ready-made policy to its role.
resource "aws_iam_role_policy_attachment" "app_assets" {
  role       = aws_iam_role.app.name
  policy_arn = module.assets.read_write_policy_arn
}

# Tell your application which bucket to use.
# module.assets.bucket_name  -> e.g. "photo-service-prod-assets-1a2b3c4d"
```

Need a second bucket for the same app? Add `purpose = "exports"` (default is
`"assets"`). As a root module: `tofu apply -var-file=minimal.tfvars`.
`examples/complete.tfvars` shows the optional inputs.

## What you get without asking

| Concern | What the module does |
|---|---|
| Naming | `<application>-<environment>-<purpose>-<8 char suffix>`; the suffix is derived from account + region so names are globally unique and stable. |
| Public exposure | All four public-access blocks on, ACLs disabled. The bucket cannot be made public. |
| Encryption at rest | Dedicated customer-managed KMS key (rotation on, S3 Bucket Key on). Uploads cannot opt out: other encryption modes, other keys and SSE-C are denied. |
| Encryption in transit | Non-TLS requests are denied. |
| Accidental deletion / overwrite | Versioning always on; old versions kept 30 days, then removed. The provided IAM policies cannot permanently delete a version. `force_destroy` is off. |
| Cost | Abandoned multipart uploads removed after 7 days; objects move to Intelligent-Tiering after 30 days; old versions expire. |
| Audit | Server access logging always on, to a private companion `<bucket>-logs` bucket (90-day retention) or your central log bucket. |
| Access for your app | Two least-privilege IAM policies (`read_only_policy_arn`, `read_write_policy_arn`) covering both S3 and the KMS key. |
| Tags | `Application`, `Environment`, `Purpose`, `ManagedBy` on everything, plus your `tags`. |

## Things you may want to turn on

| Input | When |
|---|---|
| `cors_allowed_origins` | Browser code uploads/downloads directly with presigned URLs. |
| `cloudfront_distribution_arns` | You serve images/videos to end users. Use `bucket_regional_domain_name` as the origin with Origin Access Control. |
| `expire_after_days` | Some prefixes hold disposable data, e.g. `{ "tmp/" = 7, "logs/" = 90 }`. Nothing is deleted unless you ask. |
| `noncurrent_version_retention_days` | You want a longer/shorter recovery window than 30 days. |
| `intelligent_tiering_after_days` | Set `null` to stay in S3 Standard. |
| `kms_key_arn`, `access_log_bucket_name` | Your platform team provides a shared key / central log bucket. |
| `create_iam_policies` | Your pipeline may not create IAM policies (use the `*_policy_json` outputs instead). |
| `force_destroy` | Throw-away environments only. |

## Good to know

- **Serving files to users:** never make the bucket public. Use presigned URLs
  or CloudFront (`cloudfront_distribution_arns`).
- **Uploading from code:** do not set encryption options in your S3 client; the
  bucket encrypts everything by default. If you do specify a KMS key it must be
  the full ARN in the `kms_key_arn` output.
- **Deleting:** a delete hides the object; it can be restored for
  `noncurrent_version_retention_days` days (restore the previous version in the
  console or via the API with an admin role).
- **Bring-your-own KMS key:** the module cannot edit that key's policy. For
  CloudFront, the key owner must allow `cloudfront.amazonaws.com` to
  `kms:Decrypt` for your distribution.
- **Central log bucket:** its owner must allow `logging.s3.amazonaws.com` to
  write objects from your account; it must be in the same region.
- **Not included (on purpose):** cross-region replication, Object Lock, static
  website hosting, event notifications. Ask the platform team if you need them.
- The region comes from the AWS provider / environment (`AWS_REGION`).
