# Standard S3 asset bucket

This module is the supported way for an application team to get an S3 bucket
for the files its application stores and works with: user uploads, images and
video, generated artifacts, exports, logs.

You bring almost nothing. Give the bucket a name and you get a bucket that is
private, encrypted, versioned and cleans up after itself — with none of the
ways a hand-rolled bucket usually goes wrong. If you are not sure whether you
need one of the optional inputs below, you don't; leave it out.

## Quick start

```hcl
module "assets" {
  source = "<this module's repo path>"

  name = "checkout-uploads"

  # Only needed when browsers talk to the bucket directly
  # (JavaScript uploads, presigned URLs, <img>/<video> tags):
  cors_allowed_origins = ["https://checkout.example.com"]
}
```

Then wire the bucket into your application and its IAM policies:

```hcl
locals {
  assets_bucket = module.assets.bucket_name
  assets_arn    = module.assets.bucket_arn         # bucket-level actions
  assets_obj    = module.assets.bucket_objects_arn # object-level actions
}
```

`name` is the only required input.

## What every bucket gets, whether you ask or not

| Concern | What the module does | Why you care |
| --- | --- | --- |
| Naming | `<name>-<account-id>-<region>` | S3 bucket names are shared by every AWS account on the planet; the suffix means you can never collide with another team or with your own stack in another region. Always read the name back from the `bucket_name` output. |
| Public access | All four public-access blocks on | Nobody can make this bucket world-readable, by accident or on purpose. |
| ACLs | Disabled (bucket-owner-enforced) | ACLs are a legacy mechanism; access is governed by IAM and bucket policy only, and the bucket owner owns every object written. |
| Encryption at rest | SSE-S3 (`AES256`) | Every object is encrypted with zero setup, zero extra cost and zero KMS permissions. Bring your own key via `kms_key_arn` only if you have a concrete requirement to control it. |
| Transport | Bucket policy denies all non-HTTPS requests | Nothing can read or write this bucket over plain HTTP. |
| Versioning | On | Overwrites and deletes are recoverable. |
| Old versions | Deleted after 90 days (`noncurrent_version_expiration_days`) | Versioning without expiry grows forever; 90 days is a generous undo window. |
| Broken uploads | Incomplete multipart uploads aborted after 7 days | A crashed upload leaves invisible parts that keep costing money until they are cleaned up. |
| Deletion safety | `force_destroy` off | `terraform destroy` will refuse to delete a bucket that still holds data instead of silently emptying it. |

## When you need more than the defaults

Every one of these is optional — leave them out and the defaults above apply.

**Browser access.** If your web app uploads directly to the bucket (presigned
PUT/POST) or loads assets from it, pass the origins that need access:

```hcl
cors_allowed_origins = ["https://app.example.com", "https://www.example.com"]
```

This attaches a CORS rule allowing exactly those origins to GET/HEAD/PUT/POST.
Don't use `"*"` if your requests include credentials; list your real origins.

**Your own KMS key.** `kms_key_arn = aws_kms_key.assets.arn` switches encryption
to SSE-KMS with a bucket key. Only do this when something actually requires you
to control the key — it adds KMS costs and permission requirements for every
reader and writer.

**Access logs.** `access_logs_bucket = module.log_archive.bucket_name` ships S3
server access logs to an existing bucket (which must already permit S3 log
delivery — this module does not create it).

**Transient data.** For scratch space or short-lived exports, not durable
assets, delete objects after N days:

```hcl
expiration_days = 30
```

**Cold data.** For assets that are written once and rarely read again (archived
video, old logs), move them to cheaper storage:

```hcl
infrequent_access_transition_days = 30
```

## Things this module deliberately does not do

- **Public buckets and static website hosting.** If end users need to read
  assets, put CloudFront with Origin Access Control in front of the bucket and
  keep the bucket itself private.
- **Object Lock / legal hold.** It cannot be turned off later, so it is not a
  per-team decision; talk to infrastructure first.
- **Opening up the bucket to other accounts.** Cross-account access is granted
  by the *consuming* account's IAM policies against the `bucket_arn` outputs,
  not by loosening this bucket.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| name | Base name for the bucket (`<app>-<purpose>`). Final bucket name is `<name>-<account-id>-<region>`. | `string` | n/a | yes |
| access_logs_bucket | Existing bucket to receive S3 server access logs for this bucket. | `string` | `null` | no |
| access_logs_prefix | Prefix for access logs; defaults to `s3-access-logs/<bucket-name>/`. | `string` | `null` | no |
| cors_allowed_origins | Browser origins allowed to GET/HEAD/PUT/POST on the bucket, e.g. `["https://app.example.com"]`. | `list(string)` | `[]` | no |
| expiration_days | Delete objects N days after upload. Leave unset for durable data. | `number` | `null` | no |
| force_destroy | Allow destroying a bucket that still contains objects. | `bool` | `false` | no |
| infrequent_access_transition_days | Move objects to Standard-IA N days after upload (minimum 30). | `number` | `null` | no |
| kms_key_arn | Full ARN of a KMS key for SSE-KMS encryption; default is SSE-S3. | `string` | `null` | no |
| noncurrent_version_expiration_days | Days to keep superseded/deleted object versions. | `number` | `90` | no |
| tags | Extra tags merged on top of the module's `Name` tag. | `map(string)` | `{}` | no |
| versioning_enabled | Keep every version of every object. | `bool` | `true` | no |

## Outputs

| Name | Description |
| --- | --- |
| bucket_name | Real name of the bucket (`<name>-<account-id>-<region>`). Use this in app config. |
| bucket_arn | ARN of the bucket, for bucket-level IAM actions (`s3:ListBucket`, ...). |
| bucket_objects_arn | ARN of the objects in the bucket (`<arn>/*`), for object-level IAM actions (`s3:GetObject`, ...). |
| bucket_domain_name | Global virtual-hosted-style domain of the bucket. |
| bucket_regional_domain_name | Regional virtual-hosted-style domain — use this for presigned URLs and CloudFront origins. |
