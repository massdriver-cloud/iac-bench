# Example: every optional feature of the module enabled at once. This is the
# smoke-test configuration used when changing the module - if this plans, all
# option combinations still wire up correctly.
#
#   tofu plan -var-file=full-test.tfvars
#
# The role ARNs are examples; nothing validates that principals exist.

name        = "app-assets"
environment = "dev"

# Encryption: a module-managed KMS key, plus grants through the bucket policy.
encryption            = "aws:kms"
read_write_principals = ["arn:aws:iam::123456789012:role/app-task"]
read_only_principals  = ["arn:aws:iam::123456789012:role/reporting"]

# Lifecycle: expire everything after a year, but move it to cheaper storage
# on the way there.
expire_objects_after_days                          = 365
transition_to_standard_ia_after_days               = 30
transition_to_glacier_instant_retrieval_after_days = 180
transition_to_deep_archive_after_days              = 365

# Browser access.
cors_rules = [{
  allowed_headers = ["*"]
  allowed_methods = ["GET", "PUT", "POST"]
  allowed_origins = ["https://app.example.com"]
  expose_headers  = ["ETag"]
  max_age_seconds = 3600
}]

# Audit trail: ship access logs to a shared log bucket.
access_logging = {
  target_bucket = "central-s3-access-logs"
}

# Immutability: objects cannot be altered or deleted for 30 days (with
# break-glass possible in GOVERNANCE mode).
object_lock = {
  mode = "GOVERNANCE"
  days = 30
}
