# Application assets bucket

A private S3 bucket for an application's uploads, media, generated files, and other assets. Configure the AWS provider for the target account and region, then set the application and environment:

```hcl
module "assets" {
  source = "./path-to-this-module"

  app_name    = "shop"
  environment = "prod"
}
```

The bucket name is `assets-<app_name>-<environment>-<AWS account ID>`. This keeps names predictable and scoped to the account; use a distinct application or environment name for each bucket in an account. Names are lowercase and limited to letters, digits, and hyphens. The bucket name is global across AWS, so a collision with a bucket owned by another account will need a naming adjustment.

## Defaults and access

The bucket is private: all four S3 Block Public Access settings are enabled, ACLs are disabled with `BucketOwnerEnforced`, and a bucket policy denies non-TLS requests. Objects are encrypted at rest with S3-managed keys (SSE-S3), and versioning is enabled. Destruction does not empty the bucket (`force_destroy = false`), so populated buckets cannot be accidentally deleted by a normal destroy.

This module deliberately does not grant application IAM permissions. Grant the application's workload role only the required S3 actions and bucket/object ARNs in the account's IAM configuration. No public or website access is configured.

## Outputs

- `bucket_name`: bucket name for application configuration and IAM policies.
- `bucket_arn`: bucket ARN for IAM policies.
- `bucket_region`: region selected by the AWS provider.
- `bucket_regional_domain_name`: regional S3 endpoint.
