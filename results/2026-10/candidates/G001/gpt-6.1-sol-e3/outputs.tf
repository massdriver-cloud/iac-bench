output "bucket_name" {
  description = "Bucket name for application SDK configuration."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM bucket-level actions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "objects_arn" {
  description = "Object ARN wildcard for scoped application IAM policies."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 hostname; not a public URL or a website endpoint."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "aws_region" {
  description = "Region for application SDK configuration."
  value       = var.aws_region
}
