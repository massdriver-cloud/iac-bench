# Private S3 application assets

Run this OpenTofu root module once per application and environment. It creates a general-purpose S3 bucket for private uploads, media, generated files, or application logs stored as objects. It does not create application roles or grant anyone access.

## Create a bucket

1. Use your normal AWS credentials and verify the target account. Use separate OpenTofu state for each app/environment; for team deployments, configure a shared state backend with locking before initializing.
2. Copy `minimal.tfvars` to `app.tfvars`. Change `bucket_name` to a name you control and `aws_region` to your deployment region. Bucket names must be unique across the AWS partition; use an organization/app/environment name with a unique suffix. Keep the name stable and don't include sensitive information.
3. Review and apply the plan:

   ```sh
   tofu init
   tofu plan -var-file=app.tfvars -out=app.tfplan
   tofu apply app.tfplan
   ```

Set your application's bucket name from `tofu output -raw bucket_name` and configure its AWS SDK for the same region. On initial creation, AWS recommends waiting 15 minutes after enabling versioning before issuing writes or deletes.

Give the application's execution role only the operations and prefixes it needs. For example, grant `s3:GetObject` and `s3:PutObject` on `<bucket_arn>/uploads/*`; if it needs to list, grant `s3:ListBucket` separately on `bucket_arn`, with an `s3:prefix` condition when appropriate. Don't send ACL headers in upload requests. For direct client transfers, an authorized backend can issue short-lived presigned URLs over HTTPS; cross-origin browser requests also require an S3 CORS configuration, which this module does not set up. The regional endpoint output is a hostname, not a public URL.

## Defaults and options

- **Private:** All four S3 Block Public Access settings are enabled. ACLs are disabled, and the bucket owner owns uploaded objects. The bucket policy denies non-TLS requests except for direct AWS service principals (AWS can redact network context for those calls). This exception grants no permissions. The module manages the bucket policy; don't attach a separate bucket policy resource for the same bucket.
- **Encrypted at rest:** New uploads without explicit encryption settings use S3-managed encryption (SSE-S3). Set `kms_key_arn` to an existing symmetric customer-managed key in the same region to use SSE-KMS as the default, with S3 Bucket Keys enabled. Ensure the key policy and IAM authorize the workload for the needed KMS operations (such as `kms:GenerateDataKey` for uploads and `kms:Decrypt` for reads). This changes the default for future writes; it does not enforce a specific key on every request or re-encrypt existing objects.
- **Recovery and cleanup:** Versioning helps recover from overwrites and ordinary deletes. The lifecycle rule aborts incomplete multipart uploads after seven days. By default, it does not expire completed objects or their versions. Noncurrent versions still incur storage charges. Optionally set `noncurrent_version_expiration_days` to permanently expire older versions after the specified number of days since they became noncurrent. That rule applies bucket-wide, including to existing eligible versions, but does not expire current versions. Versioning is not an immutable backup or a substitute for a retention/compliance policy.
- **Safe teardown:** OpenTofu will not forcibly empty a bucket on destroy. Before retiring it, migrate or back up anything you need, then explicitly delete all objects, noncurrent versions, and delete markers. A bucket name change requires replacement; treat name or region changes as migrations.
- **Tags:** Use `tags` for labels such as `Application`, `Environment`, and `CostCenter`. The module sets `Name` and `ManagedBy`. `bucket_name` is the only required input; if `aws_region` is omitted, the AWS provider resolves the region from its normal configuration.

This module does not enable access logging, replication, Object Lock, or CloudTrail data events. Configure those separately if required by your operational or compliance policies.
