# Standard application bucket

The standard way an application team gets an S3 bucket for its assets (user
uploads, images and videos, generated files, logs). Fill in two inputs; the
module decides everything else.

## Quick start

```hcl
module "uploads" {
  source = "<path or git URL of this module>"

  application = "checkout"   # your application's name
  environment = "prod"       # dev | test | staging | prod

  # Optional, but you almost always want these two:
  purpose               = "uploads"         # what's in the bucket
  read_write_role_names = ["checkout-api"]  # the IAM role your app runs as
}
```

Give your application the `bucket_name` output. That's it - no encryption
headers, no ACLs, no special client settings are needed.

Run directly as a root module:

```sh
tofu init
tofu apply -var-file=minimal.tfvars
```

More scenarios are in [`examples/`](./examples):

| File | Scenario |
|------|----------|
| `minimal.tfvars` | Smallest valid bucket |
| `examples/media-with-cdn.tfvars` | Browser uploads + public delivery through CloudFront |
| `examples/short-lived-exports.tfvars` | Auto-expiring files, platform-provided KMS key and central log bucket |

## What you get (and cannot turn off)

| Concern | Decision |
|---------|----------|
| Naming | `<application>-<environment>-<purpose>-<account id>-<region>` - predictable, globally unique, no random suffixes |
| Public access | Blocked at every level, permanently. Public content goes through CloudFront (`cloudfront_distribution_arns`) |
| ACLs | Disabled (`BucketOwnerEnforced`); access is controlled by policies only |
| Encryption at rest | SSE-KMS with a dedicated customer-managed key (annual rotation, 30-day deletion window, bucket key on). Uploads requesting any other encryption are refused |
| Encryption in transit | HTTPS only, TLS 1.2 or newer |
| Accidental deletion / overwrite | Versioning on; old versions recoverable for 30 days (`noncurrent_version_retention_days`). The read-write policy cannot delete versions, so the app cannot permanently destroy data |
| Cost hygiene | Abandoned multipart uploads removed after 7 days; files move to Intelligent-Tiering after 30 days; stale delete markers cleaned up |
| Audit | S3 server access logs delivered to a locked-down companion bucket (kept 365 days) or to a central log bucket |
| Application access | Least-privilege S3 + KMS permissions attached to the roles you name; the same policies are available as JSON outputs |
| Teardown | A bucket that still has files cannot be destroyed unless `force_destroy = true`, which is refused in `prod` |
| Tags | `Application`, `Environment`, `Purpose`, `ManagedBy` on everything, plus your `tags` |

## Inputs

| Name | Required | Default | What it is |
|------|----------|---------|------------|
| `application` | yes | - | Application name (lowercase, digits, hyphens; 3-24 chars) |
| `environment` | yes | - | `dev`, `test`, `staging` or `prod` |
| `purpose` | no | `"assets"` | What the bucket holds; lets one app own several buckets |
| `read_write_role_names` | no | `[]` | IAM role names that may list/read/upload/delete |
| `read_only_role_names` | no | `[]` | IAM role names that may list/read |
| `cors_allowed_origins` | no | `[]` | Web origins allowed to use pre-signed URLs from the browser |
| `cloudfront_distribution_arns` | no | `[]` | CloudFront distributions allowed to read (Origin Access Control) |
| `expire_objects_after_days` | no | `null` | Auto-delete files N days after upload |
| `noncurrent_version_retention_days` | no | `30` | Recovery window for overwritten/deleted files |
| `tags` | no | `{}` | Extra tags |
| `kms_key_arn` | no | `null` | Platform: use an existing KMS key instead of a dedicated one |
| `access_log_bucket_name` | no | `null` | Platform: deliver access logs to a central bucket instead of a companion one |
| `access_log_retention_days` | no | `365` | Platform: retention in the companion log bucket |
| `force_destroy` | no | `false` | Allow destroying a non-empty bucket (never in `prod`) |

## Outputs

`bucket_name`, `bucket_arn`, `bucket_region`, `bucket_regional_domain_name`,
`kms_key_arn`, `kms_key_alias`, `access_log_bucket_name`, `access_log_prefix`,
`read_write_policy_json`, `read_only_policy_json`.

## Things worth knowing

* **Region and credentials** come from the environment (`AWS_REGION`, etc.);
  the module contains no provider block.
* **The companion log bucket** uses SSE-S3 rather than KMS and has no access
  logging of its own. Both are deliberate: S3 log delivery cannot write to a
  KMS-encrypted destination, and logging the log bucket never terminates.
* **Bring-your-own KMS key / central log bucket**: their policies are yours to
  manage. The key policy must let the account's IAM policies (and CloudFront,
  if used) use the key; the central log bucket must accept S3 log delivery from
  this account under the prefix `<bucket name>/`.
* **Not included on purpose**: cross-region replication, Object Lock, event
  notifications and static website hosting. They need decisions an app team
  should make with the platform team, not defaults.
