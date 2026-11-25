output "bucket_name" {
  description = "Name of the created bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the created bucket. Use this to grant the application's IAM role access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "encryption" {
  description = "Default encryption in use for the bucket."
  value       = var.kms_key_arn != null ? "SSE-KMS" : "SSE-S3 (AES256)"
}
