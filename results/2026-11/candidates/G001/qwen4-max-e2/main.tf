locals {
  sse_algorithm = var.kms_key_arn == null ? "AES256" : "aws:kms"

  tags = merge(
    {
      Name      = var.name
      ManagedBy = "opentofu"
    },
    var.tags,
  )

  tiering_enabled = var.infrequent_access_transition_days != null || var.expiration_days != null
}

# -----------------------------------------------------------------------------
# The bucket. AWS generates a globally-unique suffix from the prefix, so app
# teams never have to invent a globally-unique bucket name themselves.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket_prefix = "${var.name}-"
  force_destroy = var.force_destroy

  tags = local.tags
}

# Accidental overwrites/deletes are recoverable. Always on.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest for every object, even ones uploaded without any
# encryption headers. Bucket Keys cut KMS request costs when a CMK is used.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null
  }
}

# No path to a public bucket: block every public ACL and public policy.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are disabled entirely; access is governed by IAM policies only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# -----------------------------------------------------------------------------
# Lifecycle hygiene:
#  * incomplete multipart uploads are aborted after 7 days (invisible cost leak)
#  * superseded object versions move to IA after 30 days and are deleted after
#    noncurrent_version_expiration_days
#  * current objects move to STANDARD_IA after infrequent_access_transition_days
#  * current objects are only deleted if the team explicitly opts in
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "version-and-upload-hygiene"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.noncurrent_version_expiration_days > 30 ? [1] : []

      content {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  dynamic "rule" {
    for_each = local.tiering_enabled ? [1] : []

    content {
      id     = "tiering-and-expiration"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = var.infrequent_access_transition_days != null ? [1] : []

        content {
          days          = var.infrequent_access_transition_days
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

  lifecycle {
    precondition {
      condition = (
        var.expiration_days == null ||
        var.infrequent_access_transition_days == null ||
        var.expiration_days > var.infrequent_access_transition_days
      )
      error_message = "expiration_days must be greater than infrequent_access_transition_days, otherwise objects would be deleted before they ever tier to IA."
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# -----------------------------------------------------------------------------
# Bucket policy:
#  * TLS only, for every principal and every action
#  * uploads may omit encryption headers (default encryption covers them), but
#    an upload that explicitly requests the wrong encryption is rejected
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "this" {
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

  statement {
    sid    = "DenyIncorrectEncryptionHeader"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.this.arn}/*"]

    # Both conditions must hold: the header is present AND does not match the
    # bucket's configured algorithm. Header-less uploads are allowed and get
    # encrypted by the default encryption configuration above.
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [local.sse_algorithm]
    }

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
