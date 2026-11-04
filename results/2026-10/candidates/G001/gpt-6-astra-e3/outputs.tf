output "bucket_name" {
  description = "Bucket name for application SDK configuration."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for bucket-level IAM permissions such as ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "objects_arn" {
  description = "Object ARN pattern for object-level IAM permissions; scope further to a prefix where possible."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_region" {
  description = "AWS region for application SDK configuration."
  value       = aws_s3_bucket.assets.region
}

output "bucket_regional_domain_name" {
  description = "Regional S3 hostname; objects remain private and require authorized requests."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "Configured customer-managed KMS key ARN, or null when using S3-managed encryption."
  value       = var.kms_key_arn
}
