output "bucket_name" {
  description = "Bucket name for application configuration and AWS SDK calls."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for bucket-level IAM actions. Append /* for all object keys or /prefix/* for a narrower scope."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_region" {
  description = "AWS region in which the bucket resides."
  value       = aws_s3_bucket.assets.region
}

output "bucket_regional_domain_name" {
  description = "Regional S3 hostname for the bucket; the bucket is not public."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "bucket_uri" {
  description = "S3 URI for use with tools such as the AWS CLI."
  value       = "s3://${aws_s3_bucket.assets.id}"
}
