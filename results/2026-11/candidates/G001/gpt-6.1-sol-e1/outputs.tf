output "bucket_name" {
  description = "Bucket name for application configuration. Completion waits for the security and lifecycle configuration."
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
  description = "Bucket ARN, for bucket-level IAM actions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "objects_arn" {
  description = "Object ARN pattern, for object-level IAM actions such as s3:GetObject and s3:PutObject."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint hostname; this is not a public website endpoint."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = aws_s3_bucket.assets.region
}
