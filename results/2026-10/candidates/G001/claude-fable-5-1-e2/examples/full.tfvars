# Example: a logs/exports bucket with browser access, a customer KMS key and access logging.
application = "report-builder"
environment = "prod"

expire_objects_after_days         = 90
noncurrent_version_retention_days = 14
cors_allowed_origins              = ["https://reports.example.com"]
kms_key_arn                       = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
access_log_bucket_name            = "org-s3-access-logs-123456789012"

tags = {
  Team       = "reporting"
  CostCenter = "1234"
}
