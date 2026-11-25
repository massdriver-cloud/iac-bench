output "bucket_name" {
  description = "Name (ID) of the S3 bucket — pass this to your application (e.g., S3_BUCKET_NAME)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region where the S3 bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the S3 bucket — use this when configuring a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting the bucket, or null when default SSE-S3 (AES256) encryption is used."
  value       = local.effective_kms_key_arn
}

output "kms_key_alias_name" {
  description = "Alias name of the module-managed KMS key when create_kms_key is true, or null otherwise."
  value       = var.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "read_only_policy_arn" {
  description = "ARN of the managed IAM policy granting least-privilege read-only access to the bucket (attach to your app's IAM role), or null when create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_policy_arn" {
  description = "ARN of the managed IAM policy granting least-privilege read-write access to the bucket (attach to your app's IAM role), or null when create_iam_policies is false."
  value       = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "read_only_policy_json" {
  description = "Rendered IAM policy JSON document for least-privilege read-only bucket access (useful for inline role policies)."
  value       = data.aws_iam_policy_document.app_read_only.json
}

output "read_write_policy_json" {
  description = "Rendered IAM policy JSON document for least-privilege read-write bucket access (useful for inline role policies)."
  value       = data.aws_iam_policy_document.app_read_write.json
}
