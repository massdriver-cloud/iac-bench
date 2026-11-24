data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
  dns_suffix = data.aws_partition.current.dns_suffix

  # Deterministic, globally unique S3 bucket naming (always <= 63 chars, lowercase, no dots)
  name_suffix           = "${local.account_id}-${local.region}"
  max_prefix_length     = 63 - 1 - length(local.name_suffix)
  raw_prefix            = "${var.app_name}-${var.environment}-${var.purpose}"
  trimmed_prefix        = trimsuffix(substr(local.raw_prefix, 0, local.max_prefix_length), "-")
  generated_bucket_name = "${local.trimmed_prefix}-${local.name_suffix}"
  bucket_name           = coalesce(var.bucket_name_override, local.generated_bucket_name)
  bucket_arn            = "arn:${local.partition}:s3:::${local.bucket_name}"

  # Effective KMS configuration (use_kms is always known at plan time)
  use_kms               = var.create_kms_key || var.kms_key_arn != null
  effective_kms_key_arn = var.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn

  # Ensure IAM policies exist if role attachments were requested
  should_create_iam_policies = (
    var.create_iam_policies ||
    length(var.read_write_iam_role_names) > 0 ||
    length(var.read_only_iam_role_names) > 0
  )

  # Enable Intelligent-Tiering only when objects won't expire on or before the transition day
  enable_intelligent_tiering_rule = (
    var.transition_to_intelligent_tiering_days != null &&
    (var.object_expiration_days == null || var.object_expiration_days > var.transition_to_intelligent_tiering_days)
  )

  # Standard tags applied consistently across every taggable resource; caller tags can extend or override custom keys
  default_tags = {
    Application = var.app_name
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}
