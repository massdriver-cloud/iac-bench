# Application assets bucket

A standalone OpenTofu root configuration for a private general-purpose S3 bucket. Configure AWS credentials and region through the AWS provider environment (for example `AWS_REGION` and your normal credential chain). Choose a globally unique bucket name and set it in a tfvars file:

```hcl
bucket_name = "my-company-my-app-assets-123456789012"
tags = {
  Application = "my-app"
  Environment = "production"
}
```

Run `tofu init`, then `tofu plan -var-file=your.tfvars` and `tofu apply -var-file=your.tfvars`. `minimal.tfvars` is a complete minimal example; replace its name before applying because S3 names are globally unique. Bucket names containing periods can cause TLS hostname verification problems with virtual-hosted S3 endpoints; hyphenated names are recommended.

## Defaults and access

The bucket blocks all public access, disables ACLs with bucket-owner-enforced ownership, encrypts new objects with SSE-S3, denies HTTP requests, and enables versioning. Incomplete multipart uploads are aborted after seven days. Completed objects and old versions are not automatically expired; versioning can increase storage costs. `versioning_enabled = false` suspends versioning; existing versions remain. The bucket is not emptied on destroy unless `force_destroy = true` is explicitly set; enabling it allows irreversible deletion of all objects and versions.

No application access is granted by this configuration. Grant the application's IAM role appropriate S3 permissions separately, scoped to the bucket and object ARNs exposed in the outputs. Public website hosting and ACL-based uploads are not supported. S3 access logging is not configured; if required, arrange a separate logging destination and policy. The bucket policy is managed by this configuration: do not independently replace it. SSE-S3 is the default encryption for uploads; callers can request other S3-supported encryption modes.
