# Fuller example: a media bucket that browsers upload to directly.
# Copy this file, adjust the values, and use it with:
#   tofu plan -var-file=example.tfvars

name = "photos-media"

tags = {
  team        = "growth"
  application = "photos"
  environment = "prod"
}

# Large media that is rarely re-read after its first month: tier to IA
# after 60 days. Keep objects forever (expiration_days stays unset).
transition_to_ia_days = 60

# Browser uploads via presigned URLs from the web app.
cors_rules = [
  {
    allowed_methods = ["GET", "PUT"]
    allowed_origins = ["https://photos.example.com"]
  },
]

# Optional: customer-managed KMS key (uncomment if your security team
# requires one; otherwise AES256 is used automatically).
# kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

# Optional: ship access logs to your platform team's central bucket.
# access_log_target_bucket = "acme-central-access-logs"
