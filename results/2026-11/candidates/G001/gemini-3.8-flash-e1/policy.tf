################################################################################
# Bucket Policies & IAM Helpers
#
# Enforces transport security (TLS 1.2+) and provides pre-built, least-privilege
# IAM policies so application developers don't have to craft complex S3 IAM JSON.
################################################################################

# Enforce TLS: Denies any non-HTTPS requests
data "aws_iam_policy_document" "enforce_tls" {
  count = var.enforce_tls ? 1 : 0

  statement {
    sid     = "EnforceTLSRequestsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Combine TLS enforcement policy with any optional custom policy
data "aws_iam_policy_document" "combined" {
  count = var.enforce_tls || var.custom_bucket_policy != null ? 1 : 0

  source_policy_documents = concat(
    var.enforce_tls ? [data.aws_iam_policy_document.enforce_tls[0].json] : [],
    var.custom_bucket_policy != null ? [var.custom_bucket_policy] : []
  )
}

# Attach combined policy to bucket
resource "aws_s3_bucket_policy" "this" {
  count  = var.enforce_tls || var.custom_bucket_policy != null ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.combined[0].json

  # Ensure public access block is applied before bucket policy
  depends_on = [aws_s3_bucket_public_access_block.this]
}

################################################################################
# Application IAM Helper Policy Documents
################################################################################

# Read-only policy: allows listing the bucket and downloading objects
data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

# Read-write policy: allows listing, uploading, reading, and deleting objects
data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

# Write-only policy: ideal for logging, ingestion, or drop-box style workflows
data "aws_iam_policy_document" "write_only" {
  statement {
    sid    = "ListMultipartUploads"
    effect = "Allow"
    actions = [
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "WriteObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSEncrypt"
      effect = "Allow"
      actions = [
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

################################################################################
# Optional Managed IAM Policy Resources
################################################################################

resource "aws_iam_policy" "read_only" {
  count       = var.create_iam_policies ? 1 : 0
  name_prefix = "${var.bucket_name}-read-only-"
  description = "Read-only access to S3 bucket ${var.bucket_name}"
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.merged_tags
}

resource "aws_iam_policy" "read_write" {
  count       = var.create_iam_policies ? 1 : 0
  name_prefix = "${var.bucket_name}-read-write-"
  description = "Read-write access to S3 bucket ${var.bucket_name}"
  policy      = data.aws_iam_policy_document.read_write.json
  tags        = local.merged_tags
}
