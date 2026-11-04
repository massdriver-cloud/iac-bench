output "bucket_name" {
  description = "Generated name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "S3 bucket ID, which is the same as the bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
