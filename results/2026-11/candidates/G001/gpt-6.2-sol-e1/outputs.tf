output "bucket_name" {
  description = "Bucket name, for application SDK configuration."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN, for bucket-level IAM actions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_object_arn" {
  description = "Object ARN pattern for IAM policies covering all objects. Prefer narrowing it to the application's prefix when possible."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint hostname (not a public URL)."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
