output "bucket_name" {
  description = "Name of the bucket. Use this as the bucket name in your application configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use this to scope IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket, for SDK endpoints and presigned URLs."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
