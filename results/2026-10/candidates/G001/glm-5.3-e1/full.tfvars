# Example: every optional input in use. For reference only -- the KMS key and
# the access-log bucket referenced here must already exist in your account.
#
# This is deliberately NOT the way most teams should instantiate the module:
# the defaults exist so that most teams only ever set `name` (see
# minimal.tfvars) and, at most, `cors_allowed_origins`.

name                               = "media-processor-outputs"
tags                               = { team = "media-platform", env = "prod" }
cors_allowed_origins               = ["https://media.example.com"]
kms_key_arn                        = "arn:aws:kms:us-east-1:123456789012:key/1a2b3c4d-5e6f-4a5b-8c9d-0e1f2a3b4c5d"
infrequent_access_transition_days  = 30
expiration_days                    = 365
noncurrent_version_expiration_days = 30
access_logs_bucket                 = "central-s3-access-logs"
access_logs_prefix                 = "app-buckets/media-processor-outputs/"
force_destroy                      = false
versioning_enabled                 = true
