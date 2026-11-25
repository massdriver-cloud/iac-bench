# Generated report exports that are deleted automatically after two weeks, in an
# account where the platform team provides a shared KMS key and a central
# access-log bucket.
application = "billing"
environment = "staging"
purpose     = "exports"

read_write_role_names = ["billing-worker"]

expire_objects_after_days         = 14
noncurrent_version_retention_days = 7

kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
access_log_bucket_name = "example-central-s3-access-logs"
