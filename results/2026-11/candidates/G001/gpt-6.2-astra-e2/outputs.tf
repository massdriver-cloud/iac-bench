output "bucket_name" {
  description = "Actual bucket name to pass to the application SDK."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM policies; append /* for object permissions."
  value       = aws_s3_bucket.assets.arn
}

output "region" {
  description = "AWS region containing the assets bucket."
  value       = aws_s3_bucket.assets.region
}
