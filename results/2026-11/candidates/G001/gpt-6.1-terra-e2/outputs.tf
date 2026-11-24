output "bucket_name" {
  description = "Name of the application assets bucket."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the application assets bucket (object ARNs append /*)."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint for the bucket."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
