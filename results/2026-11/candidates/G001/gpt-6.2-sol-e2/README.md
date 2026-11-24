# Application assets bucket

This OpenTofu root module creates one private, general-purpose S3 bucket for application data such as uploads, media, generated files, and application logs. Give each app environment its own bucket and state. Use your team's usual AWS credentials and remote state configuration; neither credentials nor a backend are embedded in the module.

## Quick start

Copy `minimal.tfvars` to `app.tfvars` and change `bucket_name` to a name unique within your AWS partition, for example `<org>-<app>-<env>-assets-<suffix>`. Don't put secrets or personal data in the name. Choose the region before creating the bucket: set `AWS_REGION` or set `aws_region` in the tfvars file.

```sh
tofu init
tofu plan -var-file=app.tfvars -out=app.tfplan
tofu apply app.tfplan
```

`tofu output -raw bucket_name` gives you the name to put in your app's configuration. Other outputs are `bucket_arn`, `bucket_region`, `bucket_regional_domain_name`, and `bucket_uri`.

## What you get by default

- **Private, HTTPS only.** All four S3 Block Public Access settings are enabled. The bucket policy denies non-TLS requests, and bucket-owner-enforced ownership disables ACLs. Don't send an ACL header with uploads. The module doesn't grant access: give the application's IAM role only the bucket-level and object-level actions it needs, scoped to the relevant keys. For direct browser uploads or downloads, use short-lived presigned URLs from that role rather than making the bucket public.
- **Encryption at rest.** S3-managed encryption (SSE-S3) is the default. No KMS key setup or KMS request charges are required.
- **Recovery from ordinary overwrites and deletes.** Versioning is always enabled. Completed objects and prior versions do not expire by default. S3 aborts unfinished multipart uploads after seven days and removes expired delete markers only when no object versions remain. Old versions consume storage; versioning is not an immutable backup. AWS recommends waiting 15 minutes after first enabling versioning before issuing object writes or deletes.
- **No automatic emptying on destroy.** OpenTofu will not purge a nonempty bucket; deleting it requires deliberately removing all objects, versions, and delete markers. Changing the name or region is not a data migration. Review replacement plans before applying.

## Opt in only when needed

| Input | What it changes |
| --- | --- |
| `tags` | Adds team tags such as `Application`, `Environment`, and `Owner`. The module supplies `Name` and `ManagedBy`. |
| `kms_key_arn` | Uses an existing symmetric customer-managed key in the bucket's region for default SSE-KMS, with S3 Bucket Keys enabled. Configure IAM and the key policy for the app's read/write operations. This is a default for new writes, not a policy enforcing the key on every request, and does not re-encrypt existing objects. |
| `retention` | Sets bucket-wide `current_days` and/or `noncurrent_days`. Current expiration adds a delete marker, hiding the object from ordinary reads. Noncurrent expiration permanently removes old versions, measured from when a version became noncurrent. The rules apply to existing data too; review data age and recovery needs before enabling. |
| `cors_rules` | Allows specific browser origins and methods for cross-origin requests; it doesn't grant S3 permissions. Prefer exact origins and only the methods and headers your app needs. |
| `access_logging` | Sends best-effort S3 server access logs to an existing bucket. This is separate from storing your application's own logs in the assets bucket. |

See `examples/advanced.tfvars` for syntax. Replace the placeholders and remove options you don't need. To enable server access logging, ask the destination owner for a separate bucket in the same account and region, configured for S3 log delivery (use SSE-S3, no Object Lock or Requester Pays). Its bucket policy must grant `logging.s3.amazonaws.com` `s3:PutObject` on the destination prefix, restricted by `aws:SourceArn` (the source bucket ARN) and `aws:SourceAccount` (your account ID). The default destination prefix is `s3-access/<source-bucket>/`. This module doesn't modify the destination bucket or its policy. Use CloudTrail S3 data events separately if you need an audit trail rather than best-effort access logs.
