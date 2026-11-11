data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Bucket names are global across all AWS customers. A short, deterministic
  # suffix derived from account + region makes the name unique without the app
  # team having to invent one, and stable across plans (no random provider).
  # Worst case length: 24 + 1 + 8 + 1 + 12 + 1 + 8 = 55, +5 for "-logs" = 60 (limit 63).
  name_suffix = substr(sha256("${local.account_id}/${local.region}"), 0, 8)
  bucket_name = "${var.application}-${var.environment}-${var.purpose}-${local.name_suffix}"

  # Module-owned tags win over caller tags so the standard keys can be relied on.
  tags = merge(var.tags, {
    Application = var.application
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  })

  create_kms_key    = var.kms_key_arn == null
  kms_key_arn       = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  create_log_bucket = var.access_log_bucket_name == null
  log_bucket_name   = local.create_log_bucket ? aws_s3_bucket.logs[0].id : var.access_log_bucket_name
  log_prefix        = "s3-access-logs/${local.bucket_name}/"
}

###############################################################################
# The bucket
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = local.bucket_name })
}

# ACLs are disabled: every object is owned by this account and access is
# governed by policies only. This removes a whole class of "object uploaded by
# someone else is unreadable / accidentally public" problems.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# The bucket can never be made public, regardless of later policy mistakes.
# Serve content to end users through CloudFront or presigned URLs instead.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning is always on: an overwritten or deleted object stays recoverable
# for var.noncurrent_version_retention_days (see lifecycle.tf).
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Optional CORS so browser code can use presigned URLs against the bucket.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
