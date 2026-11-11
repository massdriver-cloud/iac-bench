output "bucket_name" {
  description = "Name of the assets bucket."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the assets bucket, for use in IAM policies."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint hostname for the bucket."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
