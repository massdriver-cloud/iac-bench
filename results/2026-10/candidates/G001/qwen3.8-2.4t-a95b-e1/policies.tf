# Guardrail enforced in the bucket policy itself: plain HTTP is refused.
# Every request, from anyone, must arrive over TLS.
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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

  # Attach the public-access block first so every policy evaluation happens
  # with the block in place.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# The standard grant for an application that reads and writes objects in its
# bucket. Teams attach this ARN to their application's IAM role and never
# have to author S3 policy JSON themselves.
data "aws_iam_policy_document" "app_read_write" {
  statement {
    sid = "BucketLevel"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ObjectLevel"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectAttributes",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
}

resource "aws_iam_policy" "app_read_write" {
  count = var.create_app_policy ? 1 : 0

  name        = "${var.application}-${var.environment}-assets-${random_id.this.hex}"
  description = "Read/write access to the ${var.application} (${var.environment}) asset bucket ${local.bucket_name}."
  policy      = data.aws_iam_policy_document.app_read_write.json

  tags = local.tags
}
