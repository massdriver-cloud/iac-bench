###############################################################################
# Companion access-log bucket
#
# Created unless the caller points the module at an existing central log bucket
# via var.access_log_bucket_name. It records who accessed which object in the
# application bucket, which is what you need after an incident.
#
# It does not log access to itself (that would recurse); it holds no
# application data and only the S3 logging service can write to it.
###############################################################################

resource "aws_s3_bucket" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket        = local.log_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, {
    Name    = local.log_bucket_name
    Purpose = "access-logs-for-${var.purpose}"
  })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_versioning" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 server access log delivery only supports SSE-S3 on the destination bucket,
# so this bucket deliberately uses AES256 rather than the KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "logs" {
  count = local.create_log_bucket ? 1 : 0

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.log_bucket_arn,
      "${local.log_bucket_arn}/*",
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
    sid     = "DenyOutdatedTls"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.log_bucket_arn,
      "${local.log_bucket_arn}/*",
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

  # Only the S3 logging service, and only on behalf of our application bucket
  # in our own account, may write here.
  statement {
    sid       = "AllowS3ServerAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${local.log_bucket_arn}/${local.log_target_prefix}*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bucket_arn]
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
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}
