# Reference example showing every knob the module offers. Not needed for a
# normal instantiation — see minimal.tfvars for the smallest one.
#
#   tofu plan -var-file=example-full.tfvars

name                   = "media-files"
environment            = "prod"
versioning_enabled     = true
object_expiration_days = 90 # auto-delete objects after 90 days (logs/scratch)
cors_allowed_origins   = ["https://app.example.com"]
# access_log_bucket  = "central-log-bucket"   # must already exist and accept S3 log delivery
force_destroy = true # allow destroying the bucket while it still has objects

tags = {
  Team  = "media"
  Owner = "platform"
}
