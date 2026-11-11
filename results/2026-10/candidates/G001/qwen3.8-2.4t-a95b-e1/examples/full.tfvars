# A fully-specified example showing every optional knob. Copy this only if
# you have a specific reason; minimal.tfvars is what most teams should start
# from.

application = "photo-service"
environment = "prod"

# Transient data: delete current objects after 90 days.
object_expiration_days = 90

# Keep overwritten/deleted versions recoverable for 14 days instead of 30.
noncurrent_version_retention_days = 14

# Browser JavaScript uploads directly to S3 from these origins.
cors_allowed_origins = ["https://app.example.com"]

# Customer-managed KMS key instead of S3-managed keys.
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

# Extra tags on top of the module's standard ones.
tags = {
  Team      = "media"
  CostCode  = "MKT-1042"
  DataClass = "internal"
}
