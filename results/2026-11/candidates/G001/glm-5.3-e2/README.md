# The standard bucket, for application assets

This is the supported way for an application team to get an S3 bucket for the
assets their application stores and works with: user uploads, images and
videos, generated files, logs.

You provide **two inputs** - `name` and `environment` - and the module owns
every other decision, so every bucket in the organisation comes out the same
and comes out right. S3 knowledge is not required to use it.

```hcl
module "uploads" {
  source      = "git::ssh://git@github.com:our-org/standard-bucket.git"
  name        = "user-uploads"
  environment = "prod"
}
```

This creates a bucket named `user-uploads-prod-123456789012` (name,
environment, AWS account id) that is private, encrypted, HTTPS-only,
versioned and self-cleaning. See `examples/basic`.

## What the module decides for you

| Concern | What you get |
| --- | --- |
| Public access | **Blocked, permanently.** All four S3 public-access blocks are on, and there is deliberately no input to turn them off. To serve assets publicly, put a CDN in front of the bucket. |
| ACLs | Disabled (`BucketOwnerEnforced`): objects are always owned by the bucket owner, and accidental ACL grants cannot happen. |
| Encryption at rest | SSE-S3 by default (secure, free, nothing to manage). Set `encryption = "aws:kms"` for a dedicated customer-managed key that the module creates, aliases (`alias/<bucket-name>`), rotates, and grants your bucket principals access to. |
| Transport | The bucket policy denies every request that is not made over HTTPS. |
| Versioning | On. Overwrites and deletes keep the previous version, so mistakes are recoverable. |
| Cost of versioning | Noncurrent versions are deleted 90 days after they stop being current (`expire_noncurrent_versions_after_days`). |
| Storage hygiene | Incomplete multipart uploads are cleaned up after 7 days; expired delete markers are removed automatically. |
| Deletion safety | `tofu destroy` refuses to delete a bucket that still contains objects (any version) unless you explicitly set `force_destroy = true`. |
| Naming | `<name>-<environment>-<account-id>`: predictable, and never collides with another account's bucket in S3's global namespace. |
| Tags | `Name`, `Environment`, `ManagedBy`, `Module`, plus anything you pass in `tags`. |

## Giving your application access

Pick **one** of these two styles:

**1. List your roles, let the module write the policy** (recommended - you
never write an S3 permission yourself):

```hcl
read_write_principals = ["arn:aws:iam::123456789012:role/my-app-task"]
read_only_principals  = ["arn:aws:iam::123456789012:role/reporting-job"]
```

When the module manages the KMS key, those principals are also allowed to use
it, so SSE-KMS works out of the box.

**2. Attach the module's ready-made IAM policy to a role you manage
elsewhere:**

```hcl
resource "aws_iam_role_policy" "app_bucket_access" {
  name   = "uploads-bucket-access"
  role   = aws_iam_role.app.id
  policy = module.uploads.app_access_policy_json
}
```

The policy grants read/write on the bucket (and use of its KMS key when
SSE-KMS is on).

## Serving assets to browsers

If your web app uploads or fetches assets directly from the bucket, add CORS:

```hcl
cors_rules = [{
  allowed_headers = ["*"]
  allowed_methods = ["GET", "PUT", "POST"]
  allowed_origins = ["https://app.example.com"]
  expose_headers   = ["ETag"] # needed for browser multipart uploads
}]
```

For public delivery (product images, video), keep the bucket private and put
a CDN (CloudFront) in front of it - the `bucket_regional_domain_name` output
is the origin hostname to use.

## Cost control

Versioning hygiene is already on. Two optional knobs for data that ages:

- `expire_objects_after_days` - delete everything N days after upload
  (scratch or log-type buckets).
- Transitions to cheaper storage as objects age:
  `transition_to_standard_ia_after_days` (rarely-read),
  `transition_to_glacier_instant_retrieval_after_days` (occasionally-read
  archives), `transition_to_deep_archive_after_days` (kept-for-compliance).

See `examples/with-options`.

## Audit trail

```hcl
access_logging = {
  target_bucket = "our-central-s3-access-logs"
}
```

S3 server access logs for the bucket are delivered to that bucket under the
`<bucket-name>/` prefix (override with `target_prefix`). The target bucket
must be in the same account and must allow the S3 log delivery service to
write to it, e.g.:

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "logging.s3.amazonaws.com" },
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::our-central-s3-access-logs/*",
    "Condition": {
      "StringEquals": { "aws:SourceAccount": "123456789012" }
    }
  }]
}
```

## Immutable retention (compliance)

For data that must be provably unalterable - audit exports, signed records -
enable S3 Object Lock:

```hcl
object_lock = {
  mode = "GOVERNANCE" # administrators can break the lock in an emergency
  days = 365
}
```

Two warnings, by design:

- Enabling Object Lock is a **one-way door**. It cannot be turned off; the
  only way out is deleting the bucket. Removing `object_lock` from your
  configuration forces the bucket to be replaced.
- In `COMPLIANCE` mode nobody - not even an administrator - can delete or
  alter an object before its retention expires. `GOVERNANCE` (the default)
  keeps a break-glass path.

Lifecycle expiry cannot delete objects that are still under retention.

## What this module will not do

- Public buckets or S3 website hosting. Use a CDN in front of the bucket.
- Cross-region replication or event notifications (SQS/SNS/Lambda). If you
  need those, talk to the platform team - they interact with other teams'
  resources and are deliberately out of scope here.

## Inputs

Only `name` and `environment` are required.

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | - | **Required.** Short name of the application or asset type, e.g. `user-uploads`. First part of the bucket name. |
| `environment` | string | - | **Required.** Environment, e.g. `dev`, `staging`, `prod`. Used in the name and tags. |
| `aws_region` | string | `us-east-1` | Region the bucket is created in. |
| `bucket_name` | string | `null` | Full bucket name override (rarely needed). |
| `tags` | map(string) | `{}` | Extra tags; override the baseline tags on conflict. |
| `versioning_enabled` | bool | `true` | Keep every version of every object. |
| `encryption` | string | `aws:s3` | `aws:s3` (SSE-S3) or `aws:kms` (customer-managed key). |
| `kms_key_arn` | string | `null` | Existing KMS key for `aws:kms`; unset = module creates and manages one. |
| `kms_key_deletion_window_in_days` | number | `30` | Deletion waiting period for a module-created key (7-30). |
| `force_destroy` | bool | `false` | Allow destroying a non-empty bucket. |
| `read_write_principals` | list(string) | `[]` | IAM role/user ARNs granted read/write via the bucket policy. |
| `read_only_principals` | list(string) | `[]` | IAM role/user ARNs granted read-only via the bucket policy. |
| `abort_incomplete_multipart_uploads_after_days` | number | `7` | Clean up abandoned multipart uploads after N days. |
| `expire_noncurrent_versions_after_days` | number | `90` | Delete old object versions N days after they become noncurrent. |
| `expire_objects_after_days` | number | `null` | Delete objects N days after upload. |
| `transition_to_standard_ia_after_days` | number | `null` | Move to Standard-IA after N days (min 30). |
| `transition_to_glacier_instant_retrieval_after_days` | number | `null` | Move to Glacier Instant Retrieval after N days. |
| `transition_to_deep_archive_after_days` | number | `null` | Move to Deep Archive after N days. |
| `cors_rules` | list(object) | `[]` | CORS rules for browser access (see above). |
| `access_logging` | object | `null` | `{ target_bucket = "...", target_prefix = "..." }` for server access logs. |
| `object_lock` | object | `null` | `{ mode = "GOVERNANCE"\|"COMPLIANCE", days = N }` to enable Object Lock. |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_name` | The bucket's name (also its S3 ID). |
| `bucket_arn` | ARN of the bucket. |
| `bucket_region` | Region the bucket lives in. |
| `bucket_domain_name` | Global virtual-hosted-style domain. |
| `bucket_regional_domain_name` | Regional domain - use this for CDN origins and presigned URLs. |
| `kms_key_arn` | KMS key used for encryption, or `null` when SSE-S3 is in use. |
| `app_access_policy_json` | Ready-to-attach IAM policy JSON granting an app role read/write access to the bucket (and its KMS key, if any). |
| `bucket_policy_json` | The bucket policy the module manages, for reference. |

## Repository layout and testing

- `minimal.tfvars` - the smallest valid instantiation of the module.
- `kms-test.tfvars` - minimal + customer-managed KMS encryption.
- `full-test.tfvars` - every optional feature enabled; used as the module's
  smoke test (`tofu plan -var-file=full-test.tfvars`).
- `examples/` - copy-paste starting points for app teams.

## Notes for reviewers / platform team

- The `aws:s3` input value maps to the API's `AES256` algorithm value
  (see `encryption.tf`).
- Cross-field rules that variables alone cannot express (Object Lock requires
  versioning; `kms_key_arn` implies `aws:kms`) are enforced with `lifecycle`
  preconditions on the bucket, so misconfigurations fail at plan time with a
  plain-language message.
- The bucket policy is always present (minimum: the HTTPS-only deny), which
  is also what makes the principal grants work without any IAM-side setup.
