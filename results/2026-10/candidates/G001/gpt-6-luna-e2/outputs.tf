output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional DNS name for the bucket (not a public-access grant)."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
