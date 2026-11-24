# app-s3-bucket - the standard application asset bucket

The standard way for an application team to get an S3 bucket for the assets its
application stores and works with: user uploads, images and videos, generated
files, logs, and anything else the app reads or writes at runtime.

You fill in one obvious input (`name_prefix`) and get a bucket configured the
way the platform team would configure it. You do not need to know S3 to use
this module - every decision below has been made for you, and every default can
be overridden when you have a reason to.

Works with OpenTofu and Terraform 1.5+ with the AWS provider 5.x/6.x.

## Quick start

The one required input, plus the one most teams also need:

```hcl
module "assets" {
  source = "git::https://git.example.com/platform/app-s3-bucket.git"

  name_prefix = "acme-uploads" # the only required input

  # Only if the browser talks to S3 directly (e.g. presigned URLs):
  # cors_allowed_origins = ["https://acme.example.com"]
}

# Hand the bucket name to your application:
output "assets_bucket_name" {
  value = module.assets.bucket_name
}
```

This repository is itself a valid OpenTofu root module (that is how it is
smoke-tested): `tofu plan -var-file=minimal.tfvars`.

## What you get by default (and why)

| Concern | What the module does | Why |
| --- | --- | --- |
| Naming | Bucket is named `<name_prefix>-<account_id>-<region>` | Bucket names are one global namespace. Teams never invent names, never hit collisions, and the name is stable and predictable. A different bucket in the same account/region = a different `name_prefix`. |
| Public access | All four S3 public-access blocks enforced, and ACLs disabled (`BucketOwnerEnforced`) | Application assets are private. Serve them through your app or a CDN; nothing in this bucket can ever be exposed publicly, even by mistake. |
| Encryption | Every object encrypted at rest. Default: S3-managed keys (`AES256`) | Free, zero permissions to wire up, nothing to forget. Set `encryption = "SSE-KMS"` for a customer-managed key with your own key policy, CloudTrail trail and kill switch - the module creates and auto-rotates a dedicated key, or use `kms_key_arn` to bring your own. |
| Transport | Bucket policy denies every request that is not over HTTPS | Credentials and user data never cross the network in the clear. |
| Recoverability | Versioning enabled; overwritten/deleted object versions kept for 90 days (`noncurrent_version_expiration_days`) | Human error ("oops, wrong file") and bad deploys are recoverable. Old versions expire so storage cost does not grow forever. |
| Cost hygiene | Objects stored in the Intelligent-Tiering class; incomplete multipart uploads cleaned up after 7 days | Anything nobody reads for 30+ days automatically drops to a much cheaper tier and returns instantly when read (no retrieval fees, no latency change) - the right default for long-lived app assets. Crashed large uploads stop costing money invisibly. |

## Common recipes

### Upload/download straight from the browser (presigned URLs)

```hcl
cors_allowed_origins = ["https://app.example.com"]
```

The module adds exactly the CORS rule needed for browser GET/HEAD/PUT/POST
uploads and downloads from those origins.

### React when a file arrives (or is deleted)

```hcl
notifications = [{
  type   = "lambda" # or "sqs" / "sns"
  arn    = "arn:aws:lambda:us-west-2:123456789012:function:process-uploads"
  events = ["s3:ObjectCreated:*"]
  prefix = "incoming/"
}]
```

For Lambda destinations the module sets up the S3 invoke permission for you.
SQS/SNS destinations need their own resource policy allowing `s3.amazonaws.com`
to deliver (that is owned by the queue/topic, not this bucket).

### Keep assets only for a limited time (temp files, rotating logs)

```hcl
expire_objects_after_days = 30
```

### Tighter control over encryption

```hcl
encryption               = "SSE-KMS" # module creates + rotates a dedicated key
# or bring your own:
# encryption  = "SSE-KMS"
# kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/..."
```

### Cut storage costs on data you rarely open

```hcl
archive_objects_after_days = 90 # objects unread for 90+ days go to Glacier archive
```

Consciously opt in: archived objects take several hours to retrieve. Good for
"just in case" archives, bad for anything a user might request.

### Ship this bucket's access logs to the central log archive

```hcl
access_log_target_bucket = "platform-log-archive"
```

### Give your application's role access without writing IAM by hand

```hcl
create_app_access_policy = true
```

Then attach the `app_access_policy_arn` output to your app's execution role; it
grants exactly list/read/write/delete on this bucket (plus the KMS key if used).

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `name_prefix` | Short lowercase name for your app/assets; the bucket name is derived from it | `string` | - | yes |
| `tags` | Extra tags for all created resources | `map(string)` | `{}` | no |
| `force_destroy` | Allow destroying a non-empty bucket (**deletes all objects**) | `bool` | `false` | no |
| `versioning_enabled` | Keep old versions of objects (recoverable overwrites/deletes) | `bool` | `true` | no |
| `noncurrent_version_expiration_days` | Days to keep old object versions (0 = forever) | `number` | `90` | no |
| `expire_objects_after_days` | Days after upload to delete objects (0 = never) | `number` | `0` | no |
| `abort_incomplete_multipart_upload_days` | Days to keep unfinished multipart uploads (0 = disabled) | `number` | `7` | no |
| `enable_intelligent_tiering` | Store objects in the access-aware Intelligent-Tiering class | `bool` | `true` | no |
| `archive_objects_after_days` | Days of no access before objects move to Glacier archive (0 = never; min 90) | `number` | `0` | no |
| `encryption` | `"SSE-S3"` or `"SSE-KMS"` | `string` | `"SSE-S3"` | no |
| `kms_key_arn` | Existing KMS key for SSE-KMS (module creates one if null) | `string` | `null` | no |
| `cors_allowed_origins` | Browser origins allowed to talk to S3 directly | `list(string)` | `[]` | no |
| `access_log_target_bucket` | Existing bucket to receive this bucket's access logs | `string` | `null` | no |
| `access_log_target_prefix` | Prefix for access logs in the target bucket | `string` | `"<bucket>/"` | no |
| `notifications` | S3 event notifications (lambda / sqs / sns) | `list(object)` | `[]` | no |
| `create_app_access_policy` | Create a ready-made app read/write IAM policy | `bool` | `false` | no |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_name` | The bucket name - put this in your app configuration |
| `bucket_arn` | Bucket ARN, for IAM policies or cross-references |
| `bucket_regional_domain_name` | Bucket hostname, e.g. for a CloudFront origin |
| `kms_key_arn` | KMS key ARN when SSE-KMS is used, else null |
| `app_access_policy_arn` | ARN of the ready-made app access policy, else null |

## Changing the defaults

All defaults can be overridden, but three of them are sharp edges:

- `force_destroy = true` lets a destroy run delete every object in the bucket.
  Use it only for throwaway data.
- `versioning_enabled = false` makes overwrites and deletes unrecoverable.
  Turning it off after creation does not remove existing versions.
- `archive_objects_after_days > 0` trades instant retrieval for cheap storage
  once objects have been cold for the configured window.

## What this module deliberately does not do

- **Public buckets / static website hosting.** Application assets are served
  through your application or a CDN (e.g. CloudFront with an origin access
  control), which never needs the bucket to be public.
- **Object Lock / WORM retention.** Compliance-grade immutability has legal
  implications; talk to the platform team first.
- **Cross-account access and cross-region replication.** Sharing a bucket
  beyond its own account is a platform-team decision.
- **Receiving AWS-service-delivered logs** (ELB access logs, CloudTrail, ...).
  Those require service-specific bucket policy grants; use the central logging
  bucket for them. Storing your *application's own* logs here works fine.
