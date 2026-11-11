# A realistic "media assets" bucket: KMS encryption, app access, browser
# uploads and aging data transitioning to cheaper storage.

module "media" {
  source      = "../.."
  name        = "media"
  environment = "prod"

  # Encrypt with a dedicated, automatically rotated KMS key.
  encryption = "aws:kms"

  # Who may touch the bucket. When the module manages the KMS key, these
  # principals may also use it.
  read_write_principals = ["arn:aws:iam::123456789012:role/media-service"]
  read_only_principals  = ["arn:aws:iam::123456789012:role/media-thumbnails"]

  # Uploads straight from the browser.
  cors_rules = [{
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["https://app.example.com"]
    expose_headers   = ["ETag"] # required for browser multipart uploads
    max_age_seconds  = 3600
  }]

  # Media that stops being read after launch gets cheaper over time.
  transition_to_standard_ia_after_days                = 90
  transition_to_glacier_instant_retrieval_after_days = 365

  tags = {
    Team    = "shopfront"
    Service = "media-pipeline"
  }
}

output "bucket_name" {
  description = "The bucket this example creates."
  value       = module.media.bucket_name
}

output "app_access_policy_json" {
  description = "IAM policy to attach to the application role if you manage its policies yourself."
  value       = module.media.app_access_policy_json
}
