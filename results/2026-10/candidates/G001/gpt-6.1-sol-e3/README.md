# Application asset bucket

Standalone OpenTofu root module for private uploads, images, videos, generated files and logs. Requires OpenTofu >= 1.6, AWS provider 5.x and AWS credentials via the normal environment/credential chain. No remote modules or account-wide resources are used.

## Start here

Copy this root into your infrastructure repository. Change `bucket_name` in `minimal.tfvars` to a globally unique name you own (for example `acme-orders-prod-assets-<account-id>`), then run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`bucket_name` is the only required input. `aws_region` defaults to `us-east-1`; set it explicitly for your data residency needs. Credentials select the AWS account. Names cannot contain dots; changing the name or region replaces the bucket, not migrates the data. The supplied name is illustrative, not a reserved production name. Configure your own protected, encrypted remote state backend for team use; this root intentionally makes no assumptions about one.

## Defaults you can trust

- All four public-access blocks are on. Bucket-owner-enforced ownership disables ACLs, including object ACLs. Do not send `public-read` or legacy ACL headers from your SDK.
- Versioning is always enabled, so ordinary overwrites/deletes are recoverable by authorized operators. This is not immutable backup: principals with version-delete rights can permanently erase versions.
- All new objects are encrypted at rest with S3-managed keys (SSE-S3). Set `kms_key_arn` for a same-region customer-managed key; S3 Bucket Keys are enabled to reduce KMS request costs. The caller must provision/manage the key and its permissions. This is a default encryption configuration, not a policy enforcing a particular key when a client supplies explicit encryption headers. Restrict key use via IAM if required.
- Bucket policy denies non-TLS requests for bucket and objects, excluding direct AWS service principals to avoid breaking service delivery. It grants no access.
- Incomplete multipart uploads are aborted after seven days. Completed objects and old versions never expire by default. No automatic storage-class transitions or retrieval charges are introduced.
- `force_destroy = false`: destroying a nonempty bucket fails instead of purging application data. This does not prevent empty-bucket deletion. Destroy can remove bucket configuration before failing on a nonempty bucket; restrict infrastructure deletion privileges and review plans.
- CORS, access logging and expiration are opt-in. Public hosting, ACLs and anonymous access are intentionally not supported. Use a private CloudFront origin with a separately designed access policy if you need public distribution.

## Typical customization

```hcl
bucket_name = "acme-orders-prod-assets-123456789012"
aws_region  = "eu-west-1"
tags = {
  Application = "orders"
  Environment = "production"
  Owner       = "orders-team"
}
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "HEAD", "PUT"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
}]
```

CORS permits browser requests, not access to data. Prefer a backend application role and short-lived presigned URLs for browsers. Give the application only the object actions it needs (`s3:GetObject`, `s3:PutObject`, optionally `s3:DeleteObject`) on `objects_arn`; grant `s3:ListBucket` on `bucket_arn` only if needed. Narrow object permissions to app prefixes where possible. Do not grant infrastructure administration or `s3:DeleteObjectVersion` to ordinary app roles. Multipart workflows may also need list/abort multipart permissions. KMS callers need appropriate `kms:GenerateDataKey`/`kms:Decrypt` permissions as well as a compatible key policy. IAM roles and application credentials are deliberately outside this root.

For disposable data/log retention, set `object_expiration_days` to expire current objects. On versioned buckets this generally creates delete markers, not immediate reclamation. Separately set `noncurrent_version_expiration_days` to permanently delete old versions after they become noncurrent. Both accept positive whole days or null. These settings apply to the entire bucket, including preexisting objects; enabling them can delete data immediately based on its age. Lifecycle execution is asynchronous. Delete markers may remain. Do not enable expiration as a substitute for an intentional backup policy. Versioning and retained versions incur storage charges.

For server access logging, set `access_logging = { target_bucket = "existing-log-bucket", target_prefix = "orders/" }`. Provision that destination first in the same account/region, with a bucket policy allowing `logging.s3.amazonaws.com` `s3:PutObject` on the target prefix, constrained by this bucket's SourceArn and SourceAccount. The module does not modify another bucket's policy. Destination configuration must meet S3 logging requirements (including no Object Lock retention or SSE-KMS default encryption). Logs are best-effort and are not an audit guarantee; use separately managed CloudTrail data events for audited access. Logging is off by default to avoid recursive logging and hidden infrastructure/cost.

## Outputs and operations

Outputs expose `bucket_name`, `bucket_arn`, `objects_arn`, `bucket_regional_domain_name`, and `aws_region`. The hostname is private, not a public website endpoint. Deploy the infrastructure fully before issuing uploads. Test restore/version recovery procedures, monitor costs and access, and use replication/backups and Object Lock separately if your compliance or disaster-recovery requirements demand them. `force_destroy = true` is an explicit, irreversible purge escape hatch, not a normal production setting.
