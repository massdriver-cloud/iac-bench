output "bucket_name" {
  description = "Physical bucket name for the application's S3 SDK."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM policies. Append /prefix/* to scope object permissions."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional S3 domain name (not a public website endpoint)."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
