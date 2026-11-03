# NOT auto-loaded by OpenTofu. This is a worked example for app teams showing
# every knob the module offers (see minimal.tfvars for the smallest valid
# instantiation). Use with: tofu plan -var-file=full-example.tfvars
#
# Do not turn all of these on at once in real life — they are illustrative.
# Note: .tfvars files take literal values only (no function calls), which is
# why the extra policy below is a plain JSON string. From a module call you
# would pass data.aws_iam_policy_document.<x>.json instead.

bucket_name = "std-app-assets-full-9d21c7b4e6f048a3"

tags = {
  application = "shop"
  environment = "dev"
  team        = "checkout"
}

# Versioning off + force_destroy on: the throwaway dev-bucket combo.
versioning_enabled = false
force_destroy      = true

# Genuinely public assets (e.g. marketing images). Never for user data.
allow_public_read = true

# Browser SPA uploads/downloads.
cors_allowed_origins = ["https://app.example.com", "https://staging.example.com"]
cors_allowed_methods = ["GET", "PUT", "POST", "HEAD"]

# Customer-managed key (must exist; this ARN is illustrative).
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

# Server access logs to an existing, centrally managed log bucket.
access_log_target_bucket = "example-central-s3-access-logs"
access_log_target_prefix = "shop-assets/"

# Grant an external analytics account read access, on top of the guardrails.
additional_bucket_policy_json = <<-JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowAnalyticsAccountRead",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::std-app-assets-full-9d21c7b4e6f048a3",
      "arn:aws:s3:::std-app-assets-full-9d21c7b4e6f048a3/*"
    ]
  }]
}
JSON
