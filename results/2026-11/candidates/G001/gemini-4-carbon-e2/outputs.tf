output "bucket_name" {
  description = "Name (ID) of the S3 bucket — pass this to your application's AWS SDK configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region in which the bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_regional_domain_name" {
  description = "Region-specific DNS domain name of the bucket (recommended origin domain for CloudFront distributions)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "s3_uri" {
  description = "S3 URI of the bucket (s3://<bucket_name>)."
  value       = "s3://${aws_s3_bucket.this.id}"
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting bucket objects, or null when SSE-S3 (AES256) is used."
  value       = local.effective_kms_key_arn
}

output "read_only_policy_arn" {
  description = "ARN of the managed IAM policy granting least-privilege read-only access to this bucket (null when create_iam_policies = false)."
  value       = try(aws_iam_policy.read_only[0].arn, null)
}

output "read_write_policy_arn" {
  description = "ARN of the managed IAM policy granting least-privilege read-write access to this bucket (null when create_iam_policies = false)."
  value       = try(aws_iam_policy.read_write[0].arn, null)
}

output "read_only_policy_json" {
  description = "Rendered IAM policy JSON document for least-privilege read-only access to this bucket."
  value       = data.aws_iam_policy_document.app_read_only.json
}

output "read_write_policy_json" {
  description = "Rendered IAM policy JSON document for least-privilege read-write access to this bucket."
  value       = data.aws_iam_policy_document.app_read_write.json
}
