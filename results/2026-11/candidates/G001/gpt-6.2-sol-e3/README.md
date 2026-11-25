# Private S3 bucket for application assets

This OpenTofu root module creates one private, general-purpose S3 bucket. Use a separate bucket and state for each application/environment that needs its own access or retention boundary.

## Get started

1. Set up AWS credentials through your usual environment or profile and set `AWS_REGION` to the region where the data should live. Confirm the AWS account and region before applying.
2. Copy `minimal.tfvars` to `app.tfvars` and replace the example `bucket_name`. Use a unique name such as `myorg-gallery-prod-assets-4d9b30` (3–63 characters; lowercase letters, digits and hyphens; no dots). The name must be available in your AWS partition. Don't put sensitive information in it. Changing the name or deploying to another region is not a data migration.
3. Run:

   ```sh
   tofu init
   tofu plan -var-file=app.tfvars
   tofu apply -var-file=app.tfvars
   ```

For team deployments, use your normal shared, secured OpenTofu state setup. Keep the same state and bucket name for subsequent changes.

## What you get by default

- **Private access:** All four S3 Block Public Access settings are enabled. ACLs are disabled and the bucket owner owns uploaded objects. The bucket policy denies requests over insecure transport for non-service principals; it grants no access. AWS service principals are exempt from that deny because S3 can redact transport context on service-to-service requests.
- **Encryption at rest:** Uploads use S3-managed encryption (SSE-S3) by default. You can select an existing customer-managed key with `kms_key_arn`; this switches the bucket default to SSE-KMS and enables S3 Bucket Keys to reduce KMS request costs. This is default encryption, not a policy enforcing a specific key on every upload, and changes do not re-encrypt existing objects.
- **Recovery and cleanup:** Versioning is always enabled so accidental overwrites and ordinary deletes can be recovered while the older versions exist. S3 aborts unfinished multipart uploads seven days after initiation. No completed objects or older versions expire by default. Older versions can increase storage costs, and versioning is not a backup or an immutable retention guarantee.
- **Deletion protection for stored data:** OpenTofu will not automatically empty the bucket on destroy. To retire it, stop writers, back up data that must be retained, and deliberately remove all objects, versions and delete markers before destroying it.

## Give your app access

Use `bucket_name` and `bucket_region` to configure the app's S3 SDK. Give the app's **existing workload role** only the IAM actions it needs. For example, `s3:GetObject` and `s3:PutObject` on `<bucket_arn>/uploads/*` allow reads and writes in that prefix. If it needs to list objects, grant `s3:ListBucket` separately on `bucket_arn`, scoped with an `s3:prefix` condition if appropriate. The `bucket_objects_arn` output covers all objects and should only be used when the role needs the whole bucket. `bucket_regional_domain_name` is an endpoint, not a public URL or an access grant.

Use HTTPS and omit ACL headers. Wait for the apply to finish before enabling writers; AWS recommends waiting 15 minutes after first enabling versioning before writing or deleting objects. For private sharing, have the app issue short-lived presigned URLs. Direct browser requests from a different origin also need an explicit CORS configuration, which this baseline does not install. Cross-account access and AWS service log delivery may require additional policy statements; manage those in the same bucket policy rather than through a second resource that would overwrite it.

If using SSE-KMS, choose an enabled symmetric customer-managed key in the bucket's region. Ensure the workload role is authorized by IAM and the key policy as applicable (`kms:GenerateDataKey` for writes, `kms:Decrypt` for reads, and both for multipart uploads). Keep previous keys available while objects encrypted with them still need to be read.

## Optional inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `tags` | `{}` | Add ownership and cost tags. The `Name` tag is always the bucket name. |
| `kms_key_arn` | `null` | Use an existing KMS key instead of SSE-S3 for default encryption. |
| `noncurrent_version_expiration_days` | `null` | Permanently delete noncurrent versions after this many days in the noncurrent state. This applies bucket-wide, including to existing versions that already meet the age threshold; it does not expire current objects. Set only after agreeing on a recovery window. |
