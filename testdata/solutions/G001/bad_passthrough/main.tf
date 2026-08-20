resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = "acme-${var.team}-${var.purpose}-${random_id.suffix.hex}"
  force_destroy = var.force_destroy
  tags = merge(var.tags, {
    team        = var.team
    environment = var.environment
  })
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "transition"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_days
      storage_class = var.transition_storage_class
    }
  }
}
