output "bucket_name" {
  description = "Bucket name for application SDK configuration."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for bucket-level IAM permissions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "objects_arn" {
  description = "Object ARN pattern for object-level IAM permissions such as s3:GetObject and s3:PutObject."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 hostname, for example for a private CDN origin; not a public website URL."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = aws_s3_bucket.assets.region
}
