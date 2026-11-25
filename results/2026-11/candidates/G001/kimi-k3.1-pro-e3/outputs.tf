output "bucket_name" {
  description = "Name of the S3 bucket. Use this value in application configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket, suitable for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket, recommended for application endpoints."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS Region in which the bucket is configured."
  value       = data.aws_region.current.name
}

output "versioning_enabled" {
  description = "Whether object versioning is enabled for the bucket."
  value       = var.versioning_enabled
}

output "kms_key_arn" {
  description = "Customer-managed KMS key ARN used for encryption, or null when SSE-S3 is used."
  value       = var.kms_key_arn
}
