# Application assets bucket

Standalone OpenTofu root module: one private, general-purpose S3 bucket for uploads, media, generated files or application-written logs. No remote modules. Requires OpenTofu >= 1.6 and AWS provider >= 5, < 7; credentials come from the standard AWS credential chain. Commit the generated provider lock file.

## Start here

Copy this directory per independently managed bucket/environment, use a unique state/backend, and edit `minimal.tfvars`:

```hcl
bucket_name = "your-company-your-app-prod-assets-unique123"
# Optional; defaults to us-east-1. Place near your application.
aws_region = "us-east-1"
tags = {
  Application = "your-app"
  Environment = "production"
  Owner       = "your-team"
}
```

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The shipped minimal file supplies the only required input. Its example bucket name must be changed to a globally unique name before real deployment. Names use lowercase letters, digits and hyphens; dots are deliberately excluded for virtual-hosted TLS compatibility. Changing a bucket name or region requires replacement/migration, not a rename. Configure a secure remote state backend with locking for production; no backend or credentials are hard-coded here.

## Defaults and deliberate trade-offs

- All public access blocked, including public ACLs/policies. Bucket-owner-enforced ownership disables ACLs; uploaders must omit ACL headers (especially `public-read`). No website hosting or anonymous reads.
- S3-managed AES256 encryption at rest, with no KMS charges or key administration. Optionally set `kms_key_arn` to a same-region customer-managed key ARN; this selects SSE-KMS with S3 Bucket Keys for lower KMS request costs. The caller must arrange key policy and application KMS permissions (`kms:GenerateDataKey` for uploads and `kms:Decrypt` for reads/multipart operations). Default encryption covers uploads without encryption headers; it does not enforce a specific key against explicit per-request overrides or re-encrypt existing objects.
- HTTPS required for non-service callers; TLS older than 1.2 denied. AWS service principals are exempt from network-context checks because AWS may redact that context. This exemption grants no access.
- Versioning always enabled for recovery from accidental overwrite/deletion. A normal delete creates a delete marker; recovery requires access to prior versions. This is not immutable storage: privileged callers can permanently delete versions. No Object Lock, replication, or separate backup is provisioned.
- No automatic expiration or storage-class transitions of completed objects or old versions: losing application data by default is worse than retaining it. Retained versions incur storage charges; establish explicit retention requirements before adding expiration. Incomplete multipart uploads are aborted after seven days (unfinished uploads must finish before then or restart).
- `force_destroy = false`: a nonempty bucket, including old versions and delete markers, fails deletion. Empty buckets can still be destroyed. This is not a hard deletion lock; use deployment IAM/approval controls as well. `force_destroy = true` is an explicit opt-in for disposable environments and permanently removes objects/versions on destroy. Apply a change to this setting before a subsequent destroy.
- No application identities or access grants are created. No server access logging or CloudTrail data events by default (these need a separate destination/trail and incur cost). Application log objects work normally; this is not a turnkey AWS service log-delivery destination.

## Give the application access

Use an IAM workload role, never embedded access keys. Use `bucket_name` and `region` outputs with the S3 SDK. Grant only required actions, for example `s3:GetObject` and `s3:PutObject` on `objects_arn`; add `s3:DeleteObject` only if needed. Grant `s3:ListBucket` on `bucket_arn` only if the app lists keys. Large multipart uploads may also need `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`, and `s3:ListBucketMultipartUploads`. Scope permissions to object prefixes when appropriate. Version recovery needs separate version actions. Cross-account access requires an explicitly reviewed bucket policy in addition to identity permissions; this root owns its bucket policy, so do not attach another policy resource to the same bucket.

For user uploads/downloads, have the backend issue short-lived presigned URLs after checking authorization. Do not make the bucket public. For a public CDN, extend the policy deliberately for CloudFront Origin Access Control instead of disabling public access protections.

## Optional browser CORS

CORS is disabled unless supplied. It lets browsers use already-authorized requests; it does not authorize access or make objects public. Exact HTTPS origins only (no trailing slash, paths or wildcard origins):

```hcl
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "PUT", "HEAD"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]
```

Allow only the methods/headers your application actually needs. Test the upload flow with the headers used when signing the URL. Outputs include the bucket name, bucket and object ARNs, region and regional domain name; the domain is not a public website URL.
