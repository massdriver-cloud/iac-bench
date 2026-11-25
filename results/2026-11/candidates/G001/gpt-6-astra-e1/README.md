# Application assets bucket

A standalone OpenTofu root module for a **private general-purpose S3 bucket**. It creates resources directly, with no remote modules. Suitable for uploads, media, generated files, and application-written logs. Not a public website, backup vault, or compliance-retention solution.

## Quick start

Requires OpenTofu >= 1.6, AWS credentials from your environment/credential chain, and permission to create/configure an S3 bucket. Review which AWS account your credentials target before applying.

1. Copy `minimal.tfvars` to `app.tfvars`.
2. Change `bucket_name` to a globally unique name and `application` to your app name. Bucket names are visible in URLs: do not include secrets or personal information.
3. Optionally set `aws_region` (default `us-east-1`).
4. Run:

```sh
tofu init
tofu plan -var-file=app.tfvars -out=assets.tfplan
tofu apply assets.tfplan
tofu output
```

The supplied `minimal.tfvars` is a literal minimal example; its name is not reserved for you. Commit `.terraform.lock.hcl` for reproducible provider selection. Protect state and configure an encrypted, access-controlled remote backend with locking for team use; this root deliberately does not assume or create your organization's backend.

## Decisions made for you

- **Private only:** all four public-access blocks are enabled. ACLs are disabled with bucket-owner-enforced ownership. Do not send `public-read` ACLs or rely on uploader ownership.
- **Encrypted by default:** SSE-S3 (AES256) requires no key provisioning or KMS permissions. Optionally provide `kms_key_arn` for an existing customer-managed symmetric key in the same region; S3 Bucket Keys are then enabled to reduce KMS costs. The module does not manage that key, its policy, or its lifetime. This configures default encryption, not a policy requiring one specific key on every upload; existing objects are not re-encrypted when the default changes.
- **HTTPS required:** the bucket policy explicitly denies insecure S3 requests. It grants no access, including to the deploying application's runtime identity.
- **Versioning always enabled:** overwrites and ordinary deletes are recoverable while versions exist. A normal delete creates a delete marker; recovery requires removing that marker or copying a previous version. Privileged permanent version deletion remains possible. This is not Object Lock or a substitute for backups. AWS recommends waiting 15 minutes after first enabling versioning before initial object writes.
- **No silent data expiry:** current and noncurrent versions are retained indefinitely; there are no automatic storage-class transitions. This avoids guessing about application retention and retrieval requirements, but old versions incur storage charges. Agree on a retention policy before running high-volume logging workloads.
- **Abandoned uploads cleaned up:** multipart uploads still incomplete after seven days are aborted; completed objects are unaffected. Workloads needing longer multipart sessions need a different policy.
- **No automatic emptying:** `force_destroy = false` prevents OpenTofu from purging objects and versions to delete the bucket. Empty buckets can still be destroyed; bucket-name changes require replacement. Use IAM/change-review controls for stronger deletion protection. Intentionally retiring a populated bucket requires a separately reviewed purge of all objects, versions, and delete markers.
- Tags include `Application` and `ManagedBy=OpenTofu`, plus your `tags`. Module-owned tags take precedence.

## Giving your application access

Use a workload IAM role (not static access keys). Attach only the operations and object prefixes it needs. For example, a same-account application's identity policy could allow `s3:ListBucket` on the `bucket_arn` output and `s3:GetObject` / `s3:PutObject` on `bucket_arn/uploads/*`. Restrict listing with an `s3:prefix` condition when appropriate. Grant `s3:DeleteObject`, version operations, or multipart-management permissions only if needed. This module intentionally creates no IAM users, roles, access keys, or blanket allow policy.

With KMS, uploaders need `kms:GenerateDataKey`; readers and multipart uploaders also need `kms:Decrypt`, authorized by both IAM and the key policy as applicable. Keep the key available for the entire lifetime of the data. Cross-account access additionally requires carefully scoped bucket/key policies and is not configured by this root.

For browsers, have an authorized backend issue short-lived presigned URLs. CORS is off by default; it controls browser behavior, **not authorization**. An optional example:

```hcl
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "HEAD", "PUT"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]

tags = {
  Environment = "production"
  Team        = "application-platform"
}
```

Prefer exact origins rather than `*`. Serve public assets through an authenticated backend or a separately configured CloudFront distribution with origin access control, not by weakening the bucket's public-access blocks. CloudFront origin permissions are not created here.

## Inputs and outputs

Required inputs: `bucket_name`, `application`. Optional inputs: `aws_region` (`us-east-1`), `tags` (`{}`), `kms_key_arn` (`null`), and `cors_rules` (`[]`). See `variables.tf` for types and validation.

Outputs: `bucket_name`, `bucket_arn`, `bucket_region`, and `bucket_regional_domain_name`. Use the name and region with your SDK; the endpoint is not anonymously readable.

No access logging, CloudTrail data-event trail, replication, CDN, or monitoring infrastructure is provisioned. Those require organization-specific destinations, retention, permissions, and cost decisions. For security audit requirements, enable S3 data events in your centralized CloudTrail configuration. Application-written logs work like any other assets; delivery from AWS services may require additional service-specific policies and should be reviewed separately.
