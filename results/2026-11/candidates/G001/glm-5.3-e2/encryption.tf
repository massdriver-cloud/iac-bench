# ---------------------------------------------------------------------------
# Encryption at rest.
#
# Default: SSE-S3 (AES256) - encrypted, zero cost, zero keys to manage.
# Opt-in: a customer-managed KMS key for buckets whose access you need to
# control, audit or revoke at the key level.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Server-side encryption key for S3 bucket ${local.bucket_name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key[0].json
  tags                    = local.tags
}

# A human-friendly name so the key is recognisable in the console and in logs.
resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      # The module's "aws:s3" input is the API's "AES256".
      sse_algorithm     = var.encryption == "aws:kms" ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_id
    }

    # Bucket Keys cut KMS request costs dramatically when SSE-KMS is in use.
    bucket_key_enabled = var.encryption == "aws:kms"
  }
}

# Key policy for module-managed keys: the account keeps full control (as with
# the AWS default policy), and any principal granted access to the bucket via
# this module can also use the key, so SSE-KMS "just works" for them.
data "aws_iam_policy_document" "kms_key" {
  count = local.create_kms_key ? 1 : 0

  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(local.key_user_principals) > 0 ? [1] : []

    content {
      sid       = "AllowBucketPrincipalsKeyUse"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.key_user_principals
      }
    }
  }
}
