locals {
  tags = merge(
    {
      Name      = var.name
      ManagedBy = "opentofu"
    },
    var.tags,
  )

  # Current-object lifecycle management is only configured when the team
  # actually asked for expiry and/or an IA transition.
  manage_current_objects = var.expiration_days != null || var.transition_to_ia_days != null
}

# ---------------------------------------------------------------------------
# The bucket itself.
#
# S3 bucket names are globally unique across all AWS accounts, so the module
# generates the name from `name` plus a random suffix instead of asking app
# teams to invent a collision-free name. Consumers reference the bucket via
# the `bucket_name` / `bucket_arn` outputs.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket_prefix = "${var.name}-"
  force_destroy = var.force_destroy

  tags = local.tags

  lifecycle {
    precondition {
      condition = (
        var.expiration_days == null ||
        var.transition_to_ia_days == null ||
        var.expiration_days > var.transition_to_ia_days
      )
      error_message = "expiration_days must be greater than transition_to_ia_days (objects must live in STANDARD_IA before they are expired)."
    }
  }
}

# ---------------------------------------------------------------------------
# Security baseline — not configurable, on purpose.
# ---------------------------------------------------------------------------

# Block every flavour of public access. Assets are served through the
# application (or presigned URLs), never by making the bucket public.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely; access is governed by IAM policies only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuse any request that is not over TLS.
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

  # Public access block must be in place before a policy can be evaluated
  # against it; also avoids races on destroy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Encryption at rest, always on. AES256 by default; SSE-KMS with a Bucket Key
# (drastically reduces KMS request costs) when a customer-managed key is given.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null
  }
}

# Versioning: recoverability from accidental overwrite/delete, on by default.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ---------------------------------------------------------------------------
# Cost hygiene — the mistakes app teams make without knowing it.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Abandoned multipart uploads are invisible in the console but billed
  # forever. Always clean them up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_multipart_upload_days
    }
  }

  # Bound the cost of versioning by expiring superseded versions.
  dynamic "rule" {
    for_each = var.versioning_enabled ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  # Optional: expire and/or tier current objects (logs, scratch files, media).
  dynamic "rule" {
    for_each = local.manage_current_objects ? [1] : []

    content {
      id     = "manage-current-objects"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = var.transition_to_ia_days != null ? [1] : []

        content {
          days          = var.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "expiration" {
        for_each = var.expiration_days != null ? [1] : []

        content {
          days = var.expiration_days
        }
      }
    }
  }

  # Versioning must be configured first so noncurrent rules are accepted.
  depends_on = [aws_s3_bucket_versioning.this]
}

# ---------------------------------------------------------------------------
# Optional conveniences.
# ---------------------------------------------------------------------------

# CORS, only for buckets that browsers talk to directly.
resource "aws_s3_bucket_cors_configuration" "this" {
  for_each = length(var.cors_rules) > 0 ? { this = true } : {}

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Server access logging, only when a central logging bucket is provided.
resource "aws_s3_bucket_logging" "this" {
  for_each = var.access_log_target_bucket != null ? { this = true } : {}

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_target_bucket
  target_prefix = coalesce(var.access_log_target_prefix, "${var.name}/")
}
