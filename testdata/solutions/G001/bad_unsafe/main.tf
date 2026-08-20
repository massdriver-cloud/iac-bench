locals {
  is_prod = var.environment == "prod"

  bucket_name = "acme-${var.team}-${var.purpose}-${random_id.suffix.hex}"

  tags = {
    team        = var.team
    environment = var.environment
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = local.bucket_name
  force_destroy = !local.is_prod
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = !var.public_read
  block_public_policy     = !var.public_read
  ignore_public_acls      = !var.public_read
  restrict_public_buckets = !var.public_read
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
    id     = "storage-costs"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_days
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Access log target, prod only. Kept inside the module: consumers should not
# have to know that prod buckets need a log destination.
resource "aws_s3_bucket" "logs" {
  count         = local.is_prod ? 1 : 0
  bucket        = "acme-${var.team}-${var.purpose}-logs-${random_id.suffix.hex}"
  force_destroy = true
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
  target_prefix = "s3-access/"
}
