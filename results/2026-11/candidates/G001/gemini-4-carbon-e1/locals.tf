data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Construct a human-readable, globally unique S3 bucket name that always stays <= 63 chars.
  name_prefix      = "${var.app_name}-${var.purpose}-${var.environment}"
  name_suffix      = "${local.account_id}-${local.region}"
  candidate_name   = "${local.name_prefix}-${local.name_suffix}"
  hash_suffix      = "${substr(sha256(local.candidate_name), 0, 6)}-${local.name_suffix}"
  truncated_prefix = trim(substr(local.name_prefix, 0, 63 - 1 - length(local.hash_suffix)), "-")

  generated_bucket_name = (
    length(local.candidate_name) <= 63
    ? local.candidate_name
    : "${local.truncated_prefix}-${local.hash_suffix}"
  )

  bucket_name = var.bucket_name_override != null ? var.bucket_name_override : local.generated_bucket_name

  # Resolve encryption configuration.
  effective_kms_key_arn = var.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  use_kms               = var.create_kms_key || var.kms_key_arn != null
  sse_algorithm         = local.use_kms ? "aws:kms" : "AES256"

  # Enable Intelligent-Tiering unless objects expire so quickly (<= 30 days) that tiering cannot pay off.
  intelligent_tiering_active = (
    var.enable_intelligent_tiering &&
    (var.object_expiration_days == null || var.object_expiration_days > max(30, var.intelligent_tiering_days))
  )

  # Automatically create IAM policies if requested or if role attachments are configured.
  should_create_iam_policies = (
    var.create_iam_policies ||
    length(var.read_write_iam_role_names) > 0 ||
    length(var.read_only_iam_role_names) > 0
  )

  logging_prefix = (
    var.logging_target_prefix != null
    ? var.logging_target_prefix
    : "s3-access-logs/${local.bucket_name}/"
  )

  default_tags = {
    Application = var.app_name
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}
