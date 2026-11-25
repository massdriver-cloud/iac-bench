# A fuller example: a user-upload bucket for a web app, with browser uploads
# via presigned URLs, delivery through CloudFront and automatic cleanup of
# temporary files. Everything except application/environment is optional.

application = "photo-service"
environment = "prod"
purpose     = "uploads"

# Browser code on these sites may PUT/GET with presigned URLs.
cors_allowed_origins = ["https://app.example.com"]

# This CloudFront distribution may read objects (Origin Access Control).
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E2ABCDEFGHIJKL"]

# Delete scratch files after a week and generated reports after 90 days.
expire_after_days = {
  "tmp/"     = 7
  "reports/" = 90
}

# Keep overwritten / deleted objects recoverable for 60 days instead of 30.
noncurrent_version_retention_days = 60

tags = {
  Team       = "photos"
  CostCenter = "1234"
}

# Only if your platform team tells you to:
# kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
# access_log_bucket_name = "central-s3-access-logs"
