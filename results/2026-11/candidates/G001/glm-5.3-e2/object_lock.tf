# ---------------------------------------------------------------------------
# Optional: S3 Object Lock, for data that must be provably immutable for a
# retention period (audit, legal, regulatory).
#
# Enabling Object Lock happens at bucket creation (see main.tf) and can never
# be undone - removing `object_lock` later forces the bucket to be recreated.
# Default retention (below) is applied automatically to every object written.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock.mode
      days = var.object_lock.days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
