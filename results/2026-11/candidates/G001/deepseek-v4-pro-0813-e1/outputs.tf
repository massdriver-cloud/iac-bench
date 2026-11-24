output "bucket_id" {
  description = "The S3 bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "The S3 bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
