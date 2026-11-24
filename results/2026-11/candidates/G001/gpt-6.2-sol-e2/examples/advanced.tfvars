# Example only: replace the bucket name, origin, key ARN, and logging destination
# before applying. Remove any opt-in options you don't need.
bucket_name = "example-app-assets-7b89d2c4e1f6"
aws_region  = "us-east-1"
tags        = { Application = "example-app", Environment = "dev" }

kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

# Old versions are permanently deleted after 90 days as noncurrent versions.
retention = { noncurrent_days = 90 }

cors_rules = [{
  allowed_origins = ["https://app.example.com"]
  allowed_methods = ["GET", "PUT", "HEAD"]
  allowed_headers = ["content-type"]
  expose_headers  = ["ETag"]
}]

access_logging = {
  target_bucket = "example-central-s3-access-logs"
}
