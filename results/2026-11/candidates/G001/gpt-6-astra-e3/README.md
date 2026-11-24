# Application assets bucket

Standalone OpenTofu root module for a private, general-purpose S3 bucket. No remote modules, IAM users, credentials, public website hosting, or application roles are created.

## Quick start

Requires OpenTofu >= 1.6 and AWS provider >= 5, < 7. Supply AWS credentials through your normal AWS profile, workload identity, or environment, and select a region with `AWS_REGION` / `AWS_DEFAULT_REGION`.

1. Copy `minimal.tfvars` to `app.tfvars`.
2. Replace `bucket_name` with a globally unique name you own. Bucket names are public identifiers: do not include secrets or personal information. Names cannot be changed in place.
3. Optionally add ownership/cost tags:

```hcl
bucket_name = "mycompany-orders-assets-prod-unique123"
tags = {
  Application = "orders"
  Environment = "production"
  Owner       = "orders-team"
}
```

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=app.tfvars
tofu apply -var-file=app.tfvars
```

The supplied `minimal.tfvars` is the smallest configuration: one literal required input. Replace its example name before deployment to avoid global name collisions. Use a separate state per application/environment. Before production, configure your organization's encrypted, access-controlled remote state backend with locking; this root intentionally does not assume or provision one. Never commit state files or credentials.

## Defaults and tradeoffs

- **Always private:** all four S3 public-access blocks are enabled. Bucket-owner-enforced ownership disables ACLs and avoids cross-account upload ownership surprises. Applications should not send ACL headers.
- **Encryption at rest:** SSE-S3 (AES256), with no additional KMS request fees. Set `kms_key_arn` to an existing customer-managed key in the same region for SSE-KMS default encryption; S3 Bucket Keys reduce KMS costs. The caller must manage key availability, its key policy, and application KMS permissions. This is a default encryption setting, not a restriction on the encryption headers an authorized uploader can choose. Changing it does not re-encrypt existing objects.
- **HTTPS only:** bucket policy denies insecure S3 requests for both bucket and object operations, including requests by otherwise authorized principals. There are no Allow statements granting access. The module owns the entire bucket policy; do not manage another policy resource for this bucket.
- **Versioning always on:** overwrites and ordinary deletes preserve recoverable versions. Completed objects and noncurrent versions never expire automatically. This increases storage costs but avoids surprise data loss across diverse application workloads. Versioning is not an immutable backup: a principal with version-delete permissions can still remove versions. Allow up to 15 minutes after first enabling versioning before the first writes, as recommended by S3.
- **Failed multipart uploads cleaned up after 7 days:** completed uploads are untouched. Upload jobs must complete within that window. No storage-class transitions are imposed: retrieval fees and minimum storage durations are inappropriate defaults for unknown workloads.
- **No destructive emptying:** `force_destroy = false`. Destroying or replacing a nonempty bucket fails rather than deleting assets. An empty bucket can still be deleted. To intentionally retire a bucket, stop writers, back up what is needed, explicitly delete all versions/delete markers/incomplete uploads, then destroy. A failed destroy can remove supporting configuration before bucket deletion fails; do not use destroy as a safety check.
- **No CORS by default:** optionally allow explicit browser origins. CORS is not authorization. Public reads, static website hosting, replication, Object Lock, access-log delivery, and automatic retention/deletion policies are deliberately outside this baseline. Use a separate design for regulatory archives or AWS service log destinations with special bucket-policy requirements. Application-written logs work like any other objects.

Encryption and access settings are separate AWS API resources. Wait for a successful apply before allowing application writes. Provisioning credentials need permission to create/configure/tag/delete S3 buckets and read their settings/policies; application credentials should not have those administrative permissions.

## Application access

Use `bucket_name` and `bucket_region` outputs with an AWS SDK and your application's workload IAM role. No long-lived access keys are created. In the same account, an identity policy on that role can authorize access; cross-account access also needs a deliberately designed bucket policy and, if applicable, KMS key policy (not supported by this baseline).

Example identity policy to manage current objects, replacing the placeholders with the outputs. Narrow `OBJECTS_ARN` to the application's prefix when sharing access, and remove unneeded actions (especially delete). If restricting to a prefix, also restrict `ListBucket` with an `s3:prefix` condition.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "BUCKET_ARN"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": "OBJECTS_ARN"
    }
  ]
}
```

Version restoration should be an operator workflow with separately scoped `s3:ListBucketVersions` / `s3:GetObjectVersion` permissions. Normal app roles do not need `s3:DeleteObjectVersion`. KMS-backed reads/uploads additionally require `kms:Decrypt` / `kms:GenerateDataKey` on the selected key, allowed by both IAM and the key policy. Multipart uploads can require both KMS actions.

For browser uploads/downloads, have an authorized backend issue short-lived presigned URLs. Example optional CORS configuration:

```hcl
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "HEAD", "PUT"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]
```

Origins must be explicit HTTP(S) origins with no paths or wildcards (HTTP supports local development). CORS does not make a bucket public. Serve public-facing assets through a separately configured CDN/private-origin design, not by weakening the bucket's public-access blocks.

## Operations

Use organizational CloudTrail S3 data events for object-access auditing; ordinary CloudTrail management events do not record object reads/writes. Audit trails, alarms, budgets, backups, and retention obligations remain deployment responsibilities. Monitor version storage and periodically review whether your application needs an explicit retention policy. The module does not silently delete old application data to reduce cost.

Outputs: `bucket_name`, `bucket_arn`, `objects_arn`, `bucket_region`, `bucket_regional_domain_name`, and `kms_key_arn` (null for SSE-S3). The domain output is not a public URL. Only `bucket_name` is required; `tags` defaults to `{}`, `kms_key_arn` to null, and `cors_rules` to `[]`.
