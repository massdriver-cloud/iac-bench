output "bucket_name" {
  description = "Name (ID) of the created S3 bucket. Pass this to your application config (e.g. S3_BUCKET_NAME)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region in which the S3 bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "Regional S3 domain name for the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "iam_policy_json_read_only" {
  description = "Ready-to-use IAM policy JSON granting least-privilege read/list access to this bucket (and KMS decrypt if SSE-KMS is enabled)."
  value       = data.aws_iam_policy_document.app_read_only.json
}

output "iam_policy_json_read_write" {
  description = "Ready-to-use IAM policy JSON granting least-privilege read/write/delete access to this bucket (and KMS encrypt/decrypt if SSE-KMS is enabled)."
  value       = data.aws_iam_policy_document.app_read_write.json
}
