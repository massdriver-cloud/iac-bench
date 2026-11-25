output "bucket_id" {
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
  description = "Region-specific domain name of the S3 bucket (recommended for CloudFront origins)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region where the bucket resides."
  value       = local.region
}

output "read_only_policy_arn" {
  description = "ARN of the least-privilege read-only IAM policy (null if create_iam_policies is false)."
  value       = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_policy_arn" {
  description = "ARN of the least-privilege read-write IAM policy (null if create_iam_policies is false)."
  value       = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "read_only_policy_json" {
  description = "JSON policy document for least-privilege read-only access to this bucket."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "JSON policy document for least-privilege read-write access to this bucket."
  value       = data.aws_iam_policy_document.read_write.json
}

output "effective_configuration" {
  description = "Resolved module defaults for visibility and auditing."
  value = {
    asset_profile                      = var.asset_profile
    versioning_enabled                 = local.versioning_enabled
    encryption_algorithm               = var.kms_key_arn != null ? "aws:kms" : "AES256"
    kms_key_arn                        = var.kms_key_arn
    expiration_days                    = local.effective_expiration_days
    noncurrent_version_expiration_days = local.effective_noncurrent_days
    intelligent_tiering_enabled        = local.effective_tiering_enabled
    cors_enabled                       = length(var.cors_allowed_origins) > 0
    access_logging_enabled             = var.access_log_bucket_id != null
    eventbridge_enabled                = var.enable_eventbridge
  }
}
