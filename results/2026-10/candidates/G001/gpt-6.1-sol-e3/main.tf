resource "aws_s3_bucket" "assets" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn == null ? null : true
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]
      Condition = {
        Bool = {
          "aws:SecureTransport"       = "false"
          "aws:PrincipalIsAWSService" = "false"
        }
      }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.assets]
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "AbortAbandonedMultipartUploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = var.object_expiration_days == null ? [] : [var.object_expiration_days]
    content {
      id     = "ExpireCurrentObjects"
      status = "Enabled"
      filter {}
      expiration {
        days = rule.value
      }
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_version_expiration_days == null ? [] : [var.noncurrent_version_expiration_days]
    content {
      id     = "ExpireNoncurrentVersions"
      status = "Enabled"
      filter {}
      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.assets]
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  count  = length(var.cors_rules) == 0 ? 0 : 1
  bucket = aws_s3_bucket.assets.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

resource "aws_s3_bucket_logging" "assets" {
  count         = var.access_logging == null ? 0 : 1
  bucket        = aws_s3_bucket.assets.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix

  lifecycle {
    precondition {
      condition     = var.access_logging.target_bucket != var.bucket_name
      error_message = "Access logs must go to a separate bucket to avoid recursive logging."
    }
  }
}
