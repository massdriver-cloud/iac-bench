# Example full-featured configuration (optional features demonstrated; not auto-loaded by OpenTofu).
app_name                    = "customer-media-processing-platform"
environment                 = "staging"
purpose                     = "user-uploads"
create_kms_key              = true
kms_deletion_window_in_days = 7
cors_allowed_origins        = ["https://staging.example.com"]
cors_allowed_methods        = ["GET", "HEAD", "PUT", "POST"]
prefix_expiration_rules = {
  "tmp/"     = 7
  "exports/" = 30
}
enable_eventbridge = true
force_destroy      = true
tags = {
  CostCenter = "product-engineering"
}
