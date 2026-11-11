locals {
  # Predictable, collision-free default name: <name>-<environment>-<account-id>.
  # Including the account id means the same name/environment pair never
  # collides with another account's bucket in S3's global namespace.
  bucket_name = coalesce(
    var.bucket_name,
    "${var.name}-${var.environment}-${data.aws_caller_identity.current.account_id}",
  )

  # Baseline tags. Anything passed in `var.tags` wins on conflict.
  tags = merge(
    {
      Name        = local.bucket_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "standard-bucket"
    },
    var.tags,
  )

  # Encryption: either the caller's key, or a dedicated key we create.
  create_kms_key = var.encryption == "aws:kms" && var.kms_key_arn == null
  kms_key_id = var.encryption == "aws:kms" ? coalesce(
    var.kms_key_arn,
    try(aws_kms_key.this[0].arn, null),
  ) : null

  # Optional storage-class transitions, flattened for the lifecycle rules.
  transitions = concat(
    var.transition_to_standard_ia_after_days != null ? [{
      days          = var.transition_to_standard_ia_after_days
      storage_class = "STANDARD_IA"
    }] : [],
    var.transition_to_glacier_instant_retrieval_after_days != null ? [{
      days          = var.transition_to_glacier_instant_retrieval_after_days
      storage_class = "GLACIER_IR"
    }] : [],
    var.transition_to_deep_archive_after_days != null ? [{
      days          = var.transition_to_deep_archive_after_days
      storage_class = "DEEP_ARCHIVE"
    }] : [],
  )

  # Principals that need to use the bucket's KMS key when we manage it.
  key_user_principals = distinct(concat(var.read_only_principals, var.read_write_principals))
}
