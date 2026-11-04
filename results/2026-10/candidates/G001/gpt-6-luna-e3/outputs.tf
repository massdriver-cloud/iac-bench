output "bucket_name" {
  description = "Name of the application assets bucket."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the application assets bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional DNS name of the bucket, suitable for constructing an S3 URL."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
