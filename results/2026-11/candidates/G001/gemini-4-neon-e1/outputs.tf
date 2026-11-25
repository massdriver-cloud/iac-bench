output "bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (preferred for CloudFront origins and AWS SDK endpoints)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_region" {
  description = "AWS region where the bucket was created."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting this bucket, or null when encryption_type is \"sse-s3\"."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the module-managed KMS key, or null when using an external kms_key_arn or \"sse-s3\"."
  value       = local.create_kms_key ? aws_kms_key.this[0].key_id : null
}

output "kms_key_alias" {
  description = "Alias of the module-managed KMS key, or null when using an external kms_key_arn or \"sse-s3\"."
  value       = local.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "read_only_policy_arn" {
  description = "ARN of the least-privilege read-only IAM policy (includes S3 and KMS permissions), or null if create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_policy_arn" {
  description = "ARN of the least-privilege read-write IAM policy (includes S3 and KMS permissions), or null if create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "write_only_policy_arn" {
  description = "ARN of the least-privilege write-only IAM policy (includes S3 and KMS permissions), or null if create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.write_only[0].arn : null
}

output "read_only_policy_json" {
  description = "JSON policy document for least-privilege read-only access (useful for inline IAM policies)."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "JSON policy document for least-privilege read-write access (useful for inline IAM policies)."
  value       = data.aws_iam_policy_document.read_write.json
}

output "write_only_policy_json" {
  description = "JSON policy document for least-privilege write-only access (useful for inline IAM policies)."
  value       = data.aws_iam_policy_document.write_only.json
}

output "access_log_bucket_name" {
  description = "Name of the S3 bucket receiving server access logs, or null if access logging is disabled."
  value       = var.enable_access_logging ? local.target_access_log_bucket : null
}

output "access_log_bucket_arn" {
  description = "ARN of the companion access logs bucket created by this module, or null if using an external log bucket or logging is disabled."
  value       = local.create_access_log_bucket ? aws_s3_bucket.access_logs[0].arn : null
}

output "effective_lifecycle_settings" {
  description = "Summary of the resolved lifecycle and storage optimization settings applied to the bucket."
  value = {
    workload_type                          = var.workload_type
    versioning_enabled                     = var.enable_versioning
    intelligent_tiering_enabled            = local.effective_intelligent_tiering
    object_expiration_days                 = local.effective_object_expiration_days
    archive_after_days                     = local.effective_intelligent_tiering ? null : local.effective_archive_after_days
    noncurrent_version_transition_days     = local.enable_noncurrent_transition ? local.effective_noncurrent_transition_days : null
    noncurrent_version_expiration_days     = var.enable_versioning ? local.effective_noncurrent_expiration_days : null
    abort_incomplete_multipart_upload_days = local.effective_abort_multipart_days
  }
}
