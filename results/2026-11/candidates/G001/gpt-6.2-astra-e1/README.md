# Application asset bucket

Deploy one private, general-purpose S3 bucket per app/environment. Set your usual AWS credentials and `AWS_REGION` (choose the region where your app and its data belong). Use a separate OpenTofu state for each deployment.

```sh
cp minimal.tfvars app.tfvars
# Edit name_prefix in app.tfvars; optionally add tags = { Owner = "media" }.
tofu init
tofu plan -var-file=app.tfvars -out=app.plan
tofu apply app.plan
tofu output -raw bucket_name
```

Pass `bucket_name` to your app's S3 client. The prefix gets a unique suffix; changing the prefix requests a new bucket, not a rename or data migration. `bucket_arn` is for IAM and `bucket_regional_domain_name` is for integrations.

The bucket blocks public access, disables ACLs, requires HTTPS and defaults to S3-managed encryption with no key to administer. Do not send ACLs on uploads. The module grants no application permissions: grant your workload role only the S3 actions it needs on the appropriate object prefix (and bucket-level actions such as listing only if needed). For temporary access from a client, use short-lived presigned HTTPS URLs rather than making objects public.

Versioning lets you recover earlier uploads and undo ordinary deletes. Current and previous versions are retained until explicitly removed and incur storage costs; no blanket expiration is safe for arbitrary application data. Unfinished multipart uploads are aborted after seven days. Destroy does not purge data: intentionally remove all object versions and delete markers before retiring the bucket. Versioning is not a substitute for an independent backup.
