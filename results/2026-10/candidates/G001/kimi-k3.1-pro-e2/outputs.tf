output "bucket_name" {
  description = "Name of the application asset bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the application asset bucket, suitable for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the application asset bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "access_log_bucket_name" {
  description = "Name of the dedicated access-log bucket, or null when access logging is disabled."
  value       = try(aws_s3_bucket.logs[0].id, null)
}

output "access_log_bucket_arn" {
  description = "ARN of the dedicated access-log bucket, or null when access logging is disabled."
  value       = try(aws_s3_bucket.logs[0].arn, null)
}
