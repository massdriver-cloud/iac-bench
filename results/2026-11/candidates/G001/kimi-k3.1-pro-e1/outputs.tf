output "bucket_id" {
  description = "S3 bucket id, suitable for references to other S3 resources."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "Name of the application asset bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket. Append /* when constructing an IAM resource ARN for its objects."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region in which the bucket resides."
  value       = aws_s3_bucket.this.region
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name for application and presigned URL configuration."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
