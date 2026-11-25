# Application assets bucket

Provision one private S3 bucket per application environment. Copy `minimal.tfvars` to `app.tfvars` and change `bucket_prefix` to a descriptive name such as `photos-staging-assets`. S3 names are shared across accounts; the provider adds a unique suffix. Optionally add `tags = { Owner = "media-team" }`.

With AWS credentials and your chosen `AWS_REGION` set in the environment, run:

```sh
tofu init
tofu plan -var-file=app.tfvars -out=assets.plan
tofu apply assets.plan
tofu output -raw bucket_name
```

Use the output name in your app's SDK configuration. The bucket grants no application permissions by itself. Grant your workload's IAM role only the operations it needs: for example, `s3:PutObject` on `<bucket_arn>/uploads/*` for simple uploads. `s3:ListBucket`, if needed, uses the bucket ARN itself. Use HTTPS and omit ACL headers. For temporary client access, issue scoped, short-lived presigned URLs rather than making the bucket public.

**Data handling:** Objects are encrypted by default with S3-managed keys. Versioning preserves prior contents across overwrites and ordinary deletes; recover an earlier version through the S3 console's *Show versions* view. Completed objects and their old versions are not expired automatically and incur storage charges until removed. Only unfinished multipart uploads are cleaned up after seven days. This is not immutable storage or a separate backup.

Changing the prefix replaces the bucket; it does not migrate data. OpenTofu will not empty a bucket on destroy. For intentional retirement, verify your backup and retention requirements before explicitly removing every version and delete marker.
