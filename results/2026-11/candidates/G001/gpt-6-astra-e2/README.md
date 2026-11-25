# Application assets bucket

A standalone OpenTofu root configuration for a **private, general-purpose S3 bucket**. No remote modules. Only `bucket_name` is required. Use one root/state per application and environment; keep state in your organization's secured remote backend (backend bootstrapping is intentionally not included).

## Quick start

1. Install OpenTofu >= 1.6 and configure AWS credentials and `AWS_REGION` through your normal environment/profile. The deployment identity needs permission to create/configure S3 buckets and their policies; application identities should not have these infrastructure permissions.
2. Copy `minimal.tfvars` to your environment's tfvars file and replace the example name with a globally unique name, e.g. `acme-avatar-assets-prod-unique123`. Bucket names are visible in URLs; do not put secrets in them.
3. Run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
tofu output
```

If using a different tfvars filename, use that filename in both commands. Set tags when possible:

```hcl
bucket_name = "acme-avatar-assets-prod-unique123"
tags = {
  Application = "avatars"
  Environment = "prod"
  Owner       = "profile-team"
}
```

## Defaults and tradeoffs

- **Private:** all four public-access blocks are enabled, and bucket-owner-enforced ownership disables ACLs. Applications must not send ACL headers such as `public-read`. Public websites are not supported. Serve private assets using authorized SDK requests/presigned URLs; a private CDN requires separately designed origin access and an appropriate extension to this module's bucket policy.
- **HTTPS only:** a bucket policy denies all S3 actions over insecure transport. The module owns the bucket policy; do not attach a second policy resource to the same bucket.
- **Encrypted at rest:** S3-managed AES-256 by default, without KMS request charges. Optionally set `kms_key_arn` to an existing customer-managed key in this region. KMS mode enables S3 Bucket Keys to reduce KMS request costs. Key creation, rotation, policy and deletion protection are the key owner's responsibility. This is default encryption, not a policy enforcing a particular encryption header/key on every upload.
- **Recoverable overwrites/deletes:** versioning is always enabled. Deleting a key normally creates a delete marker; previous versions remain. This is not immutable storage or a backup: a principal allowed to delete versions can permanently remove them. Restore by copying an older version or removing the relevant delete marker.
- **No surprise data expiry:** completed objects and old versions never expire automatically. They incur storage charges until explicitly deleted; establish an application-specific retention policy before using this for high-volume logs. No default storage-class transitions, replication, access-log bucket, CloudTrail trail or Object Lock are provisioned. Add audit/backup/retention controls where required.
- **Incomplete uploads:** multipart uploads left unfinished for seven days are aborted to limit orphaned-part storage charges. Clients with uploads intentionally spanning longer than seven days need a different policy.
- **Deletion safety:** `force_destroy` is hardcoded false. Destroy/replacement fails for a nonempty bucket, including versions and delete markers. This is not `prevent_destroy`: an empty bucket can be destroyed. Decommissioning requires explicit, separately authorized deletion of every version and delete marker before `tofu destroy`. Changing the name replaces the bucket; it does not migrate data. Never reuse a retired name for sensitive links.

## Grant the application access

This module does not create users, credentials or roles and grants no application access. Grant the application's existing IAM role only the actions it needs, using the outputs:

- `s3:GetObject` and/or `s3:PutObject` on `objects_arn`, preferably narrowed to an application prefix.
- `s3:ListBucket` on `bucket_arn` only if listing is needed; scope with `s3:prefix` where possible.
- `s3:DeleteObject` only if application deletes are needed. Do not normally grant `s3:DeleteObjectVersion`.
- Multipart clients may also need `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`, and `s3:ListBucketMultipartUploads` on the appropriate object/bucket resources.

Same-account IAM permissions are sufficient unless other policies deny access. Cross-account access needs an explicitly designed bucket policy as well. KMS users additionally need appropriate `kms:GenerateDataKey` (writes) and `kms:Decrypt` (reads and multipart uploads) permissions and authorization in the key policy. The HTTPS deny remains effective regardless of IAM allows.

## Browser uploads/downloads (optional)

CORS is disabled unless configured. Browser access still needs IAM authorization or a presigned URL. Restrict origins to your application's actual origins; CORS is not an authorization boundary.

```hcl
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "HEAD", "PUT"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]
```

Optional inputs: `tags` (map, default `{}`), `kms_key_arn` (string, default `null`), and `cors_rules` (list, default `[]`). Required input: `bucket_name` (string, no default). Names intentionally exclude dots for virtual-hosted HTTPS compatibility.

Outputs: `bucket_name`, `bucket_arn`, `objects_arn`, `bucket_regional_domain_name`, and `bucket_region`. Use `bucket_name` and `bucket_region` with the AWS SDK; the hostname output does not imply anonymous access.

After initial enablement, AWS recommends allowing up to 15 minutes for versioning propagation before the first object writes. Provision the bucket before deploying writers. Validate with `tofu validate` and `tofu plan -var-file=minimal.tfvars`; a plan does not prove name availability, deploy-time permissions, KMS key usability or actual application access.
