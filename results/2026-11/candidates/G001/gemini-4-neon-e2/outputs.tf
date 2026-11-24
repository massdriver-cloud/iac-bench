output "bucket_name" {
  description = "Name (ID) of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket (use this for CloudFront origins and regional endpoints)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region where the S3 bucket resides."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting this bucket (null if encryption_mode = 'aes256')."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "Key ID of the module-managed KMS key (null if using an external key or encryption_mode = 'aes256')."
  value       = local.create_kms_key ? aws_kms_key.this[0].key_id : null
}

output "kms_key_alias" {
  description = "Alias of the module-managed KMS key (null if using an external key or encryption_mode = 'aes256')."
  value       = local.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "read_only_policy_arn" {
  description = "ARN of the least-privilege read-only IAM policy for this bucket and its KMS key (null if create_iam_policies = false)."
  value       = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_policy_arn" {
  description = "ARN of the least-privilege read-write IAM policy for this bucket and its KMS key (null if create_iam_policies = false)."
  value       = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "read_only_policy_json" {
  description = "Least-privilege read-only IAM policy document JSON for this bucket and its KMS key."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "Least-privilege read-write IAM policy document JSON for this bucket and its KMS key."
  value       = data.aws_iam_policy_document.read_write.json
}

output "access_log_bucket_name" {
  description = "Name of the S3 bucket receiving server access logs (null if enable_access_logging = false)."
  value       = local.access_log_bucket_name
}

output "access_log_bucket_arn" {
  description = "ARN of the module-managed companion access-log bucket (null if using an external target bucket or if access logging is disabled)."
  value       = local.create_access_log_bucket ? aws_s3_bucket.access_logs[0].arn : null
}

output "effective_configuration" {
  description = "Summary of the resolved security, lifecycle, and observability settings applied to this bucket."
  value = {
    use_case                              = var.use_case
    encryption_mode                       = var.encryption_mode
    versioning_enabled                    = local.versioning_enabled
    intelligent_tiering_enabled           = local.intelligent_tiering_enabled
    object_expiration_days                = local.object_expiration_days
    noncurrent_version_transition_ia_days = local.versioning_enabled ? local.noncurrent_version_transition_ia_days : null
    noncurrent_version_expiration_days    = local.versioning_enabled ? local.noncurrent_version_expiration_days : null
    access_logging_enabled                = var.enable_access_logging
    eventbridge_enabled                   = var.enable_eventbridge
    cors_enabled                          = local.cors_enabled
  }
}
