locals {
  # AWS provider v6 renamed `aws_region.name` to `aws_region.region`; accept either.
  region = try(data.aws_region.current.region, data.aws_region.current.name)

  # Deterministic, globally unique bucket name. S3 bucket names are a single
  # global namespace; deriving the name from the account and region means app
  # teams never have to invent (or debug collisions in) a bucket name, and the
  # name stays stable across replans.
  bucket_name = "${var.name_prefix}-${data.aws_caller_identity.current.account_id}-${local.region}"

  tags = merge(
    { Name = local.bucket_name },
    var.tags,
  )

  uses_kms       = var.encryption == "SSE-KMS"
  create_kms_key = local.uses_kms && var.kms_key_arn == null

  # The KMS key that encrypts the bucket: either brought in by the caller or
  # created by this module. null when the bucket uses S3-managed keys.
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (local.create_kms_key ? aws_kms_key.this[0].arn : null)

  # Lifecycle rules, reduced to the ones actually configured. A value of 0
  # means "leave this to the team" and the rule is dropped entirely.
  lifecycle_rules = [
    for rule in [
      {
        id                         = "abort-incomplete-multipart-uploads"
        abort_days                 = var.abort_incomplete_multipart_upload_days
        noncurrent_expiration_days = 0
        object_expiration_days     = 0
        transition_to_it           = false
      },
      {
        id                         = "store-in-intelligent-tiering"
        abort_days                 = 0
        noncurrent_expiration_days = 0
        object_expiration_days     = 0
        transition_to_it           = var.enable_intelligent_tiering || var.archive_objects_after_days > 0
      },
      {
        id                         = "expire-noncurrent-object-versions"
        abort_days                 = 0
        noncurrent_expiration_days = var.versioning_enabled ? var.noncurrent_version_expiration_days : 0
        object_expiration_days     = 0
        transition_to_it           = false
      },
      {
        id                         = "expire-objects"
        abort_days                 = 0
        noncurrent_expiration_days = 0
        object_expiration_days     = var.expire_objects_after_days
        transition_to_it           = false
      },
    ] : rule if rule.abort_days > 0 || rule.noncurrent_expiration_days > 0 || rule.object_expiration_days > 0 || rule.transition_to_it
  ]
}
