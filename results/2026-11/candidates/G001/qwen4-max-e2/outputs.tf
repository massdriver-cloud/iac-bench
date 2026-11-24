output "bucket_name" {
  description = "Generated (globally unique) name of the bucket. Use this in your application configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use in IAM policies granting your application access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Region-specific DNS name of the bucket (preferred for SDK/endpoint configuration)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "sse_algorithm" {
  description = "Server-side encryption algorithm applied to all objects (AES256 or aws:kms)."
  value       = local.sse_algorithm
}
