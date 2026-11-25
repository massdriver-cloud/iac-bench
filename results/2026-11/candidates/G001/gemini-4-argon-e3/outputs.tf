output "bucket_id" {
  description = "The name (ID) of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "The AWS region this bucket resides in."
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "The bucket domain name (s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The region-specific domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "read_only_iam_policy_json" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read-only access to the bucket (including KMS decrypt if KMS is configured)."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_iam_policy_json" {
  description = "Ready-to-attach IAM policy JSON granting least-privilege read/write access to the bucket (including KMS encrypt/decrypt if KMS is configured)."
  value       = data.aws_iam_policy_document.read_write.json
}
