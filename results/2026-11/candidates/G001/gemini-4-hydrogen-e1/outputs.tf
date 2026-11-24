output "bucket_name" {
  description = "Name (ID) of the created S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the S3 bucket (bucket.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket — prefer this for SDKs, presigned URLs, and CloudFront origins."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region in which the bucket resides."
  value       = aws_s3_bucket.this.region
}

output "versioning_enabled" {
  description = "Effective versioning status of the bucket."
  value       = local.effective_versioning_enabled
}

output "kms_key_arn" {
  description = "KMS key ARN used for default encryption, or null if SSE-S3 (AES256) is used."
  value       = var.kms_key_arn
}

output "iam_read_write_policy_json" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read/write access to this bucket (and KMS key, if configured)."
  value       = data.aws_iam_policy_document.app_read_write.json
}

output "iam_read_only_policy_json" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read-only access to this bucket (and KMS decrypt, if configured)."
  value       = data.aws_iam_policy_document.app_read_only.json
}
