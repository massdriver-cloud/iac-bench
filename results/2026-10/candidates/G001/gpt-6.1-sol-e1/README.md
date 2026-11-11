# Application asset bucket

A standalone OpenTofu root configuration for one application's private S3 assets. It creates the resources directly; there are no remote module dependencies. Use a separate working directory/state for each application/environment. Only `bucket_name` is required.

## Quick start

1. Copy this configuration into your application's infrastructure directory.
2. Set AWS credentials and `AWS_REGION` (or use your AWS profile). The deploying identity needs permission to create and configure S3 buckets and bucket policies.
3. Copy `minimal.tfvars` to your own variable file and change the bucket name to a globally unique name. The sample name is illustrative, not reserved for you.
4. Run:

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Use a securely managed remote state backend with locking for team/production deployments; backend selection is intentionally left to your organization. Do not commit credentials, state, saved plans, or `.terraform/`. Commit the generated provider lock file.

An application/environment example:

```hcl
bucket_name = "acme-orders-prod-assets-123456789012"
tags = {
  Application = "orders"
  Environment = "prod"
  Owner       = "orders-team"
  CostCenter  = "engineering"
}
```

## Decisions you do not need to make

| Setting | Standard behavior |
| --- | --- |
| Access | Private. All four public-access-block controls enabled; no public grants. |
| Ownership | Bucket-owner-enforced ownership, ACLs disabled. Upload clients must omit ACL headers. |
| Transport | Explicit deny for non-HTTPS requests. Direct AWS service principals are exempt because service network context can be redacted; this exemption does not grant access. |
| Encryption | S3-managed AES-256 encryption by default, with no KMS request charges. Optional existing KMS key supported. |
| Recovery | Versioning always enabled. Overwrites and ordinary deletes retain prior versions. |
| Cleanup | Abort incomplete multipart uploads after seven days. Completed objects and prior versions are never expired or transitioned automatically. |
| Destruction | `force_destroy = false`: OpenTofu will not empty the bucket for you. A nonempty bucket, including versions and delete markers, blocks bucket deletion. An empty bucket can still be destroyed. |
| Browser access | No CORS configuration unless explicitly requested. |

Versioning is not immutable backup: a principal with `s3:DeleteObjectVersion` can permanently delete versions. Do not grant that permission to ordinary application roles. Versions incur storage charges until deliberately removed. Renaming the bucket requires replacement; plan and migrate data explicitly rather than treating a name change as a rename. This module does not provide Object Lock, replication, or backup.

The seven-day multipart limit also applies to unusually long-running legitimate uploads. Finish uploads within that window. There is intentionally no object expiration default: uploads, logs, and generated files have different retention needs, and a generic module should not silently delete them.

## Application permissions and serving assets

This configuration creates no IAM users, access keys, or application role. Attach a least-privilege policy to your existing workload role. For a read/write application, the shape is:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "<bucket_arn output>"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "<objects_arn output>"
    }
  ]
}
```

These are placeholders, not a directly deployable policy. Drop unneeded actions and restrict object prefixes for each workload. Multipart SDK workflows may additionally need `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`, and bucket-level `s3:ListBucketMultipartUploads`. No application access is granted by the module's bucket policy; it only adds a transport deny. Cross-account access needs an explicitly reviewed extension to that policy and the caller's IAM policy; do not manage a second competing bucket policy resource.

For downloads/uploads from a browser, use short-lived HTTPS presigned URLs issued by your application. For public delivery, put an authenticated origin such as CloudFront OAC in front of S3 and deliberately extend the bucket policy with a distribution-scoped grant; do not turn off public access blocking. Static website hosting and CDN setup are outside this configuration.

### Optional CORS

CORS tells browsers which cross-origin operations are allowed; it is not authentication or authorization. Use exact trusted origins, particularly for uploads:

```hcl
cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "HEAD", "PUT"]
  allowed_headers = ["content-type", "x-amz-*"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]
```

### Optional customer-managed encryption

```hcl
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
```

Supply an existing enabled symmetric encryption key in the same region. This module does not create or modify keys or key policies. Application roles and the key policy must permit the appropriate `kms:GenerateDataKey` and `kms:Decrypt` operations. S3 Bucket Keys are enabled to reduce KMS calls. KMS introduces request costs, quotas, and an extra availability dependency; key deletion can render data unreadable.

Encryption configuration sets the default for new writes, not retroactive encryption of existing objects or enforcement of a particular key against explicit upload headers. If compliance requires key enforcement, add an explicitly reviewed bucket-policy restriction; changing the key here does not re-encrypt old versions.

## Scope and outputs

Outputs: `bucket_name`, `bucket_arn`, `objects_arn`, `bucket_region`, and `bucket_regional_domain_name`. The regional hostname does not imply public access. The `bucket_name` output waits for bucket configuration, useful if this code is later called locally as a module.

Access logging and CloudTrail data events are not enabled here: central audit destinations, retention, permissions, and costs are organization-specific. Integrate this bucket with your organization's auditing, monitoring, cost controls, and backup systems where required. This is a safe general-purpose asset bucket, not an audit-log archive or a compliance certification.
