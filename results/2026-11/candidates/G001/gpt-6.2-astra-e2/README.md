# Application assets bucket

Deploy this directory once per application environment, with separate OpenTofu state for each deployment. Use your normal AWS credentials and set `AWS_REGION` to the application's region.

```sh
cp minimal.tfvars app.tfvars
# Edit bucket_label in app.tfvars, e.g. bucket_label = "gallery-prod"
tofu init
tofu plan -var-file=app.tfvars -out=assets.plan
tofu apply assets.plan
tofu output -raw bucket_name
```

`bucket_label` is the only required input. Keep it stable: S3 buckets cannot be renamed. OpenTofu adds a suffix to avoid global name collisions; configure your SDK with the `bucket_name` and `region` outputs rather than constructing a name. Add `tags = { Team = "media" }` to the tfvars if desired.

**Access:** The bucket is private, requires HTTPS, and has object ACLs disabled. Don't send a public-read ACL on uploads. The module grants no application access: give the app's existing IAM role just the actions it needs. For example, scope `s3:GetObject` and `s3:PutObject` to `${bucket_arn}/uploads/*` (substitute the `bucket_arn` output); `s3:ListBucket`, if needed, goes on the bucket ARN itself. Use short-lived presigned URLs for clients that need temporary access to an object.

**Data handling:** S3 encrypts new uploads by default with S3-managed keys; no key setup is needed. Versioning retains earlier revisions after overwrites and ordinary deletes. Completed objects and their versions have no automatic expiry, so retained versions incur storage charges. Only incomplete multipart uploads are aborted after seven days. Destruction will not automatically empty the bucket: deliberate decommissioning requires removing all versions and delete markers first.
