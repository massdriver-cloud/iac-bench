# ------------------------------------------------------------------------------
# Companion Server Access-Log Bucket (created when no central log bucket is set)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket        = local.companion_log_bucket_name
  force_destroy = var.allow_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.companion_log_bucket_name
    Purpose = "s3-access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# AWS recommends SSE-S3 (AES256) for S3 server access log target buckets.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_logging_retention_days
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*",
    ]

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

  statement {
    sid     = "DenyOutdatedTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  # Least-privilege S3 server access log delivery with confused-deputy protection.
  statement {
    sid       = "AllowS3ServerAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/s3-access-logs/${aws_s3_bucket.this.id}/*"]

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

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.create_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.access_logs,
    aws_s3_bucket_ownership_controls.access_logs,
  ]
}

# ------------------------------------------------------------------------------
# Server Access Logging Attachment on Primary Bucket
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = var.enable_access_logging ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = local.access_log_bucket_name
  target_prefix = "s3-access-logs/${aws_s3_bucket.this.id}/"

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }

  depends_on = [
    aws_s3_bucket_policy.access_logs,
    aws_s3_bucket_ownership_controls.access_logs,
  ]
}
