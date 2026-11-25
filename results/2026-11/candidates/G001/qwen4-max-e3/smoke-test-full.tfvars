# Exercise every optional code path (used as a smoke-test var file).
name = "smoke-test-full"

tags = {
  team        = "platform"
  environment = "test"
}

kms_key_arn                        = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
versioning_enabled                 = true
noncurrent_version_expiration_days = 14
abort_multipart_upload_days        = 3
expiration_days                    = 365
transition_to_ia_days              = 90

cors_rules = [
  {
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = ["https://app.example.com"]
    expose_headers  = ["ETag"]
  },
]

access_log_target_bucket = "acme-central-access-logs"
force_destroy            = true
