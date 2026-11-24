output "bucket_name" {
  description = "Bucket name for application SDK configuration."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM bucket-level permissions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "objects_arn" {
  description = "Object ARN pattern for IAM object-level permissions; narrow to an application prefix if possible."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint (not a public website)."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "region" {
  description = "AWS region for application SDK configuration."
  value       = var.aws_region
}
