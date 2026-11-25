# ---------------------------------------------------------------------------
# The bucket and its always-on protections.
#
# This module deliberately provides no way to turn these off: a standard
# bucket is private, un-ACL-able, and versioned. If an application needs to
# serve assets publicly, put a CDN in front of the bucket instead.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
  tags   = local.tags

  # Buckets with data in them must not disappear by accident. When this is
  # false, destroy fails while the bucket still holds objects (any version).
  force_destroy = var.force_destroy

  # Object Lock must be enabled at bucket creation time, so the decision is
  # taken here rather than in a separate resource.
  object_lock_enabled = var.object_lock != null

  lifecycle {
    precondition {
      condition     = var.object_lock == null || var.versioning_enabled
      error_message = "Object Lock requires versioning. Either set versioning_enabled = true or remove object_lock."
    }

    precondition {
      condition     = var.kms_key_arn == null || var.encryption == "aws:kms"
      error_message = "kms_key_arn is only used with encryption = \"aws:kms\". Either set encryption = \"aws:kms\" or remove kms_key_arn."
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Disable the legacy ACL machinery entirely: every object is owned by the
# bucket owner and ACL-based (often accidental) grants simply cannot happen.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# All four public-access blocks, unconditionally. There is no variable for
# this on purpose.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
