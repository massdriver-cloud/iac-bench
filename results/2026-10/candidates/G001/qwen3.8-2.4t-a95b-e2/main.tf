# ---------------------------------------------------------------------------
# Standard application asset bucket
#
# Every resource below encodes a deliberate default. Application teams are
# expected to set var.name and var.environment only; see README.md for the
# reasoning behind each decision.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = local.force_destroy

  tags = local.common_tags
}

# No asset bucket should ever be reachable from the public internet.
# Applications (and any CDN in front of them) go through IAM-authenticated or
# pre-signed URLs instead.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are a legacy footgun; access is governed exclusively by IAM and the
# bucket policy.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Every object encrypted at rest by default. SSE-S3 keeps this zero-effort:
# no keys to create, manage or pay for.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning on by default: user uploads and generated assets are precious,
# and this is the only real protection against accidental deletes and
# overwrites. The status is managed (Enabled/Suspended) rather than the
# resource being created/destroyed, so toggling it never loses history.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Aborted/failed multipart uploads leave orphaned parts behind that are
  # billed like normal objects. Clean them up, always.
  rule {
    id     = "AbortIncompleteMultipartUploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning protects data but doubles storage if left alone; prune stale
  # versions after the retention window so protection stays affordable.
  dynamic "rule" {
    for_each = var.versioning_enabled ? [1] : []

    content {
      id     = "ExpireStaleVersions"
      status = "Enabled"

      noncurrent_version_expiration {
        noncurrent_days = var.retention.expire_noncurrent_after_days
      }

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # Optional handling of current objects: expiry (ephemeral assets such as
  # logs) and/or a move to STANDARD_IA (large, rarely-read media).
  dynamic "rule" {
    for_each = local.manage_current_objects ? [1] : []

    content {
      id     = "ManageCurrentObjects"
      status = "Enabled"

      dynamic "transition" {
        for_each = var.retention.transition_to_ia_after_days != null ? [var.retention.transition_to_ia_after_days] : []

        content {
          days          = transition.value
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "expiration" {
        for_each = var.retention.expire_objects_after_days != null ? [var.retention.expire_objects_after_days] : []

        content {
          days = expiration.value
        }
      }
    }
  }

  # Lifecycle rules that reference versions must be applied after versioning
  # is configured on the bucket.
  depends_on = [aws_s3_bucket_versioning.this]
}

# Defense in depth: refuse any request that is not made over TLS.
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json

  # The public-access block must be in place before a bucket policy is
  # attached, otherwise the policy evaluation can race with it.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
