output "bucket_id" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use this in IAM policies granting application access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket, for SDK endpoints."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "encryption" {
  description = "How objects are encrypted at rest by default."
  value       = local.encryption_kms ? "SSE-KMS" : "SSE-S3 (AES256)"
}
