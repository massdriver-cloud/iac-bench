# Application assets S3 bucket

This root module provisions a private S3 bucket for application assets. It enables
S3-managed encryption at rest, object versioning, bucket-owner-enforced ownership,
all four S3 Block Public Access controls, and a bucket policy denying requests
that do not use TLS. The bucket is not made public and the module does not grant
application IAM access; grant the application's IAM role only the object and
bucket actions it needs in your application's identity policy.

## Use

Configure the AWS provider/credentials in the normal AWS environment, then set
these required values:

```hcl
bucket_name     = "my-app-assets-prod-123456"
application_name = "my-app"
environment      = "prod"
```

The bucket name must be globally unique and use 3-63 lowercase letters, digits,
dots, or hyphens, beginning and ending with a letter or digit. (AWS may reserve
some otherwise valid names.) `force_destroy` defaults to false to protect
stored data. Additional tags can be passed via `tags`; module-standard tags take
precedence. See `minimal.tfvars` for a small root-module plan example.
