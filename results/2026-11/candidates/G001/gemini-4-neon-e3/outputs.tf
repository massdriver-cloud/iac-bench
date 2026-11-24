output "bucket_name" {
  description = "Name (ID) of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket (use this as the origin domain for CloudFront)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region in which the S3 bucket is created."
  value       = local.region
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the bucket (managed or caller-provided), or null when using SSE-S3."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "Key ID of the module-managed KMS key, or null when using SSE-S3 or a caller-provided KMS key."
  value       = local.create_kms_key ? aws_kms_key.this[0].key_id : null
}

output "kms_key_alias" {
  description = "Alias of the module-managed KMS key, or null when using SSE-S3 or a caller-provided KMS key."
  value       = local.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "read_only_iam_policy_arn" {
  description = "ARN of the managed least-privilege read-only IAM policy (attach to roles that only read bucket objects), or null if create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_iam_policy_arn" {
  description = "ARN of the managed least-privilege read-write IAM policy (attach to application roles that read/write bucket objects), or null if create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "read_only_iam_policy_json" {
  description = "JSON policy document granting least-privilege read-only access to the bucket (and its KMS key if enabled)."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_iam_policy_json" {
  description = "JSON policy document granting least-privilege read-write access to the bucket (and its KMS key if enabled)."
  value       = data.aws_iam_policy_document.read_write.json
}

output "effective_configuration" {
  description = "Summary of the resolved storage, encryption, and lifecycle settings applied to this bucket."
  value = {
    workload_profile                       = var.workload_profile
    encryption_type                        = var.encryption_type
    versioning_enabled                     = local.versioning_enabled
    intelligent_tiering_enabled            = local.enable_intelligent_tiering
    object_expiration_days                 = local.object_expiration_days
    noncurrent_version_expiration_days     = local.versioning_enabled ? local.noncurrent_version_expiration_days : null
    abort_incomplete_multipart_upload_days = local.abort_incomplete_multipart_upload_days
    cors_enabled                           = length(var.cors_allowed_origins) > 0
    access_logging_enabled                 = var.access_log_bucket_name != null
    eventbridge_enabled                    = var.enable_eventbridge
    transfer_acceleration_enabled          = var.enable_transfer_acceleration
  }
}
