###############################################################################
# Access logging: who read / wrote / deleted what is always recorded.
#
# By default the module creates a small private companion bucket for the logs.
# Organisations with a central log bucket pass var.access_log_bucket_name.
###############################################################################

resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id

  target_bucket = local.log_bucket_name
  target_prefix = local.log_prefix

  # Log delivery must already be permitted when logging is switched on.
  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_s3_bucket" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket        = "${local.bucket_name}-logs"
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = "${local.bucket_name}-logs" })
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# S3 log delivery only supports SSE-S3 on the destination bucket, so the log
# bucket uses S3-managed keys rather than the KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning makes tampering with / deleting log files recoverable.
resource "aws_s3_bucket_versioning" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Logs are kept for a bounded time, then removed for good a week later.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

data "aws_iam_policy_document" "logs" {
  count = local.create_log_bucket ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs[0].arn, "${aws_s3_bucket.logs[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Only the S3 logging service, and only on behalf of the bucket above, may
  # write here.
  statement {
    sid       = "AllowS3AccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs[0].arn}/${local.log_prefix}*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.logs[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.logs,
    aws_s3_bucket_ownership_controls.logs,
  ]
}
