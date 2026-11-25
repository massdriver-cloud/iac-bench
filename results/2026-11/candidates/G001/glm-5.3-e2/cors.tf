# ---------------------------------------------------------------------------
# CORS, for applications that talk to S3 straight from the browser
# (direct uploads, or <img>/<video> tags on cross-origin pages).
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      # Only pass these through when set (and non-empty); an empty list is
      # not a valid value for S3.
      allowed_headers = cors_rule.value.allowed_headers != null && length(cors_rule.value.allowed_headers) > 0 ? cors_rule.value.allowed_headers : null
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers != null && length(cors_rule.value.expose_headers) > 0 ? cors_rule.value.expose_headers : null
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}
