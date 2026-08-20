locals {
  is_prod       = var.environment == "prod"
  bucket_name   = "assets-${var.purpose}-${random_id.suffix.hex}"
  force_destroy = var.force_destroy != null ? var.force_destroy : !local.is_prod

  tags = merge(var.extra_tags, {
    managed-by  = "opentofu"
    environment = var.environment
  })
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = local.bucket_name
  force_destroy = local.force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  count  = local.is_prod ? 1 : 0
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = var.transition_days > 0 ? [1] : []

    content {
      id     = "transition"
      status = "Enabled"

      filter {}

      transition {
        days          = var.transition_days
        storage_class = var.transition_storage_class
      }
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_expiration_days > 0 ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_expiration_days
      }
    }
  }
}

resource "aws_s3_bucket" "logs" {
  count         = local.is_prod ? 1 : 0
  bucket        = "assets-${var.purpose}-logs-${random_id.suffix.hex}"
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = local.is_prod ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = local.is_prod ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "assets" {
  count         = local.is_prod ? 1 : 0
  bucket        = aws_s3_bucket.assets.id
  target_bucket = aws_s3_bucket.logs[0].id
  target_prefix = var.log_prefix
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "logs" {
  count  = local.is_prod ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
