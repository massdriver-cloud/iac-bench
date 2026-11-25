# ---------------------------------------------------------------------------
# Optional: S3 server access logging, for buckets whose access patterns need
# an audit trail. Logs go to a bucket you already operate (usually a shared
# logging bucket); the module defaults the prefix to "<bucket-name>/".
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = coalesce(var.access_logging.target_prefix, "${local.bucket_name}/")
}
