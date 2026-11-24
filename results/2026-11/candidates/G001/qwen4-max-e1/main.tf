# ---------------------------------------------------------------------------
# Standard application asset bucket.
#
# Design decisions (owned by this module, not the app teams):
#   * Private by default and impossible to make public through this module:
#     all four public-access blocks are on and ACLs are disabled entirely.
#   * Encryption at rest is always on (SSE-S3 by default, SSE-KMS with Bucket
#     Keys if a key ARN is supplied).
#   * Versioning is always on so overwrites/deletes are recoverable; old
#     versions are expired automatically to bound cost.
#   * TLS-only access enforced by bucket policy.
#   * Incomplete multipart uploads are aborted after 7 days so failed uploads
#     don't silently accrue storage charges.
#   * Deterministic, account-scoped, DNS-safe bucket name.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.application}-${var.environment}-assets-${data.aws_caller_identity.current.account_id}"

  use_kms       = var.kms_key_arn != null
  sse_algorithm = local.use_kms ? "aws:kms" : "AES256"

  tags = merge(var.tags, {
    Name        = local.bucket_name
    Application = var.application
    Environment = var.environment
    ManagedBy   = "opentofu"
  })
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = local.tags
}

# ACLs are disabled: access is governed exclusively by IAM and bucket policy.
# This removes the most common way buckets accidentally become public.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Belt and braces: block every avenue to public access, regardless of any
# policy or ACL anyone might attach out-of-band later.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Recoverability: keep every overwrite/delete as a noncurrent version.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest, always on. With a customer-managed KMS key, S3 Bucket
# Keys are enabled to cut KMS request costs by ~99%.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# Storage hygiene + cost control for the versioning safety net.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be enabled before noncurrent-version rules are accepted.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# Deny any request that is not over TLS.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.tls_only.json

  # Public access block must be in place before attaching a policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
