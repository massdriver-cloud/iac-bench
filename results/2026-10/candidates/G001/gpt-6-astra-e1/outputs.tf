output "bucket_name" {
  description = "Bucket name to pass to the application's AWS SDK."
  value       = aws_s3_bucket.assets.id
  depends_on = [
    aws_s3_bucket_public_access_block.assets,
    aws_s3_bucket_ownership_controls.assets,
    aws_s3_bucket_versioning.assets,
    aws_s3_bucket_server_side_encryption_configuration.assets,
    aws_s3_bucket_policy.assets,
    aws_s3_bucket_lifecycle_configuration.assets,
    aws_s3_bucket_cors_configuration.assets,
  ]
}

output "bucket_arn" {
  description = "Bucket ARN for IAM bucket-level permissions; append /* for object-level permissions."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_region" {
  description = "Region to configure in the application's AWS SDK."
  value       = aws_s3_bucket.assets.region
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint hostname. This is not a public website or a grant of access."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
