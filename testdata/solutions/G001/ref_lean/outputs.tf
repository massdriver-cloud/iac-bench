output "bucket_name" {
  description = "Name of the asset bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the asset bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name — the value to wire the bucket to anything downstream."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
