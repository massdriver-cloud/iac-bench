output "bucket_name" {
  description = "The generated, globally-unique name of the bucket. Use this in your application configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use this when granting your application's IAM role access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket domain name (bucket.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific bucket domain name — prefer this for SDK/endpoint configuration."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "encryption_algorithm" {
  description = "Server-side encryption algorithm in effect (AES256 or aws:kms)."
  value       = var.kms_key_arn == null ? "AES256" : "aws:kms"
}
