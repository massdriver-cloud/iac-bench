# Full-featured example configuration for validation/reference.
app_name         = "media-api"
environment      = "staging"
purpose          = "uploads"
owner            = "media-platform"
workload_profile = "assets"
encryption_type  = "kms"

cors_allowed_origins = [
  "https://app.staging.example.com",
]

enable_eventbridge = true

custom_lifecycle_rules = [
  {
    id              = "tmp-uploads"
    prefix          = "tmp/"
    expiration_days = 1
  },
]

tags = {
  CostCenter = "CC-1000"
}
