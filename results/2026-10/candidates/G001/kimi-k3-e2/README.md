# app-assets-bucket

The standard way for an application team to get an S3 bucket for the assets
its app stores and works with: user uploads, images and videos, generated
files, logs.

You should not need to know S3 to use this. Fill in a bucket name, and trust
the module for everything else.

## Usage

```hcl
module "assets" {
  source = "…/app-assets-bucket"

  bucket_name = "acme-payments-assets-prod"

  tags = {
    team    = "payments"
    service = "billing"
  }
}

output "bucket_arn" { value = module.assets.bucket_arn }
```

`bucket_name` is the only required input.

## What you decide

| Variable | Default | When to change it |
|---|---|---|
| `bucket_name` | — (required) | Globally unique; name it after your app + environment |
| `tags` | `{}` | Add team / service / cost-center |
| `enable_versioning` | `true` | Turn off only for regenerable throwaway data |
| `expiration_days` | `0` (keep forever) | Set e.g. `365` for a logs bucket |
| `cors_allowed_origins` | `[]` (no CORS) | Set your web origin for direct browser uploads |
| `logging_target_bucket` | none | Point at your org's log bucket if you need access logs |
| `kms_key_arn` | SSE-S3 | Supply a KMS key only if compliance requires one |
| `force_destroy` | `false` | Only for dev/test buckets you tear down often |
| `noncurrent_version_expiration_days` | `90` | How long overwritten/deleted versions linger |
| `abort_incomplete_multipart_upload_days` | `7` | Cleanup window for failed uploads |
| `extra_bucket_policy_json` | none | Grant a CDN / other account access, on top of the guardrails |

## What the module decides for you (and you cannot turn off)

- **Private.** All four public-access-block settings are on; ACLs are
  disabled (`BucketOwnerEnforced`). Access flows through IAM and bucket
  policy only.
- **Encrypted at rest.** SSE-S3 by default; your KMS key if you supply one.
- **TLS only.** A bucket policy denies any request that isn't HTTPS.
- **Versioned by default**, so an accidental overwrite or delete isn't
  data loss.
- **Self-cleaning.** Abandoned multipart uploads are aborted after 7 days;
  superseded versions are purged after 90 days. No silent cost creep.

## Outputs

| Output | Use it for |
|---|---|
| `bucket_name` | App config |
| `bucket_arn` | IAM policies |
| `bucket_uri` | CLI scripts (`s3://…`) |
| `bucket_regional_domain_name` | CDN origins / endpoint config |
| `bucket_region` | SDK / client config |
