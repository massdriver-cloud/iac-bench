output "bucket_name" {
  description = "Name of the assets bucket."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the assets bucket. Object ARNs append /*."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = aws_s3_bucket.assets.region
}

output "bucket_regional_domain_name" {
  description = "Regional S3 DNS name of the bucket."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
