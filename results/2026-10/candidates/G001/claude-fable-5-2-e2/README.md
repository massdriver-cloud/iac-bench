# Standard application bucket

The standard way for an application team to get an S3 bucket for its assets
(user uploads, images and videos, generated files, logs). Fill in two inputs;
the module makes every other decision.

## Usage

```hcl
app_name    = "photo-service"
environment = "prod"

# Optional, but you almost always want it: the role(s) your app runs as.
read_write_role_names = ["photo-service-api"]

# Optional: only if browsers upload/download directly with pre-signed URLs.
# cors_allowed_origins = ["https://photos.example.com"]

# Optional: for buckets of temporary/generated files or logs.
# purpose                   = "exports"
# expire_objects_after_days = 14
```

Then give the `bucket_name` output to your application.

## What you get without asking

| Concern | Decision |
|---|---|
| Naming | `<app>-<env>-<purpose>-<8-char suffix>`; deterministic and globally unique per account/region |
| Public access | Fully blocked (all four settings). ACLs disabled (`BucketOwnerEnforced`) |
| Encryption at rest | SSE-KMS with a dedicated, auto-rotating key (or your own via `kms_key_arn`), bucket keys on; uploads requesting other encryption are denied |
| Encryption in transit | Non-TLS and TLS < 1.2 requests are denied |
| Recovery | Versioning on; overwritten/deleted objects are recoverable for 30 days. The read-write policy cannot permanently delete versions |
| Cost | Incomplete multipart uploads aborted after 7 days; old versions expire; objects move to Intelligent-Tiering after 30 days |
| Audit | Server access logs go to a dedicated, locked-down log bucket (90-day retention) or a central one via `access_log_bucket_name` |
| Access | Least-privilege `read-write` and `read-only` IAM policies are created and attached to the roles you name |
| Deletion | `tofu destroy` refuses to delete a non-empty bucket unless `force_destroy = true` |

## Deliberately not included

- **Public/static website hosting** - put a CDN in front of the bucket instead.
- **Cross-region replication and Object Lock** - these are compliance/DR
  decisions that need a second region or irreversible settings; they should
  not be a silent default.
