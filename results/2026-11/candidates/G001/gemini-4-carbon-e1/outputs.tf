output "bucket_name" {
  description = "Name of the S3 bucket (pass this to your application's S3 client configuration)."
  value       = aws_s3_bucket.this.id
}

output "bucket_id" {
  description = "ID of the S3 bucket (same as bucket_name)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region in which the S3 bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "Global S3 domain name of the bucket (<bucket>.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific S3 domain name of the bucket (use this when configuring a CloudFront Origin)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "encryption_algorithm" {
  description = "Server-side encryption algorithm enforced on the bucket (\"AES256\" or \"aws:kms\")."
  value       = local.sse_algorithm
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting bucket objects, or null when using default SSE-S3 (AES256) encryption."
  value       = local.effective_kms_key_arn
}

output "kms_key_alias" {
  description = "Alias of the module-created KMS key, or null when create_kms_key is false."
  value       = var.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "read_only_iam_policy_arn" {
  description = "ARN of the managed IAM policy granting read-only access to this bucket (and KMS decrypt if applicable)."
  value       = local.should_create_iam_policies ? aws_iam_policy.read_only[0].arn : null
}

output "read_write_iam_policy_arn" {
  description = "ARN of the managed IAM policy granting read-write access to this bucket (and KMS encrypt/decrypt if applicable)."
  value       = local.should_create_iam_policies ? aws_iam_policy.read_write[0].arn : null
}

output "read_only_iam_policy_json" {
  description = "IAM policy JSON document for read-only bucket access (useful if embedding an inline role policy)."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_iam_policy_json" {
  description = "IAM policy JSON document for read-write bucket access (useful if embedding an inline role policy)."
  value       = data.aws_iam_policy_document.read_write.json
}

output "app_environment_variables" {
  description = "Ready-to-inject map of standard S3 environment variables for ECS tasks, Kubernetes pods, or Lambda functions."
  value = merge(
    {
      S3_BUCKET_NAME   = aws_s3_bucket.this.id
      S3_BUCKET_ARN    = aws_s3_bucket.this.arn
      S3_BUCKET_REGION = aws_s3_bucket.this.region
    },
    local.effective_kms_key_arn != null ? { S3_KMS_KEY_ARN = local.effective_kms_key_arn } : {}
  )
}
