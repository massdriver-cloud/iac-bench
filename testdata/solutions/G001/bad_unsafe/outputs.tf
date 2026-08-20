output "bucket_name" {
  description = "Name of the asset bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the asset bucket."
  value       = aws_s3_bucket.assets.arn
}
