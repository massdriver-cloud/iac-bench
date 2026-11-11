# Application assets bucket

A private, versioned S3 bucket for application assets. Configure AWS credentials and region through the standard AWS environment/provider settings, then replace the globally unique example name in `minimal.tfvars` and run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`bucket_name` is required and must be globally unique within the AWS partition. `tags` is an optional map. Outputs provide the bucket name, ARN, and regional endpoint. Grant application roles the necessary S3 permissions separately; the bucket policy only denies insecure transport and does not grant access.

Public access is blocked, ACLs are disabled (bucket owner enforced), default encryption uses S3-managed keys (SSE-S3), and versioning is enabled. Incomplete multipart uploads are aborted after seven days. Object versions are not automatically expired: storage charges can grow, and deleting an object normally leaves prior versions. The bucket is not force-destroyed; empty all object versions and delete markers before destroying it. This configuration does not enable access logging or replication; configure those separately if required by your organization. AWS may take time to propagate versioning settings on a newly created bucket before writes should begin.
