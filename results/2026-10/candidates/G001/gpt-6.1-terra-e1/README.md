# Application assets bucket

A private, general-purpose S3 bucket for application assets. This directory is a
standalone OpenTofu root configuration. Copy it for each bucket, configure AWS
credentials and region through the environment, and replace the example name
with a globally unique name you control:

```hcl
# my-bucket.tfvars
bucket_name = "my-company-my-app-assets-prod-123456789012"
tags = {
  Application = "my-app"
  Environment = "production"
}
```

```sh
tofu init
tofu plan -var-file=my-bucket.tfvars
tofu apply -var-file=my-bucket.tfvars
```

`minimal.tfvars` is a minimal example for planning; its name is only an example
and may already be taken. Choose an S3-compliant name unique across AWS. Bucket
names cannot be changed in place. Use the outputs `bucket_name`, `bucket_arn`,
and `bucket_regional_domain_name` to configure your application and its IAM
policies.

## Defaults and operation

* All four bucket-level public access blocks are enabled, and ACLs are disabled
  using bucket-owner-enforced ownership. This bucket is not a public website.
* Requests over HTTP are denied by the bucket policy. Application principals
  still need appropriate IAM permissions; the module grants no access. Presigned
  HTTPS URLs can be used for controlled sharing.
* Versioning is enabled to help recover overwritten or deleted objects. Old
  versions are retained indefinitely and incur storage costs; a normal delete
  creates a delete marker, not permanent removal. AWS recommends waiting 15
  minutes after first enabling versioning before issuing writes or deletes.
* New objects use S3-managed encryption (SSE-S3) by default. Optionally set
  `kms_key_arn` to a customer-managed KMS key ARN in the bucket's region to use
  SSE-KMS with S3 Bucket Keys. The key policy and callers' IAM permissions must
  permit KMS use; KMS charges may apply. This is default encryption, not a
  policy preventing clients from explicitly requesting another encryption mode.
* Incomplete multipart uploads are aborted after seven days; completed objects
  and versions are not automatically expired. Set application-specific
  retention separately if needed, taking care not to overwrite the lifecycle
  configuration managed here.
* `force_destroy` defaults to false so a non-empty bucket cannot accidentally
  be destroyed. Setting it to true allows deletion of all objects and versions
  during destroy; use only when that loss is acceptable. It does not prevent
  authorized users from deleting objects outside OpenTofu.

The module does not configure server access logging, cross-region replication,
object lock, CORS, or application IAM permissions. Enable these separately if
your application's requirements call for them; do not manage a second bucket
policy or lifecycle configuration for this bucket, as each is a single S3
configuration managed here.
