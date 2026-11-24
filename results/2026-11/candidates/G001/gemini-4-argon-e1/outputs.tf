output "bucket_name" {
  description = "Name (ID) of the created S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region where the S3 bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "Global domain name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the S3 bucket (useful for CloudFront origins)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "iam_policy_json_read_only" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read/list access to this bucket (including KMS decrypt permissions if kms_key_arn is used)."
  value       = data.aws_iam_policy_document.app_read_only.json
}

output "iam_policy_json_read_write" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read/write/delete access to this bucket (including KMS permissions if kms_key_arn is used)."
  value       = data.aws_iam_policy_document.app_read_write.json
}
