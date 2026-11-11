output "bucket_name" {
  description = "The bucket's name. This is what your application configuration needs to talk to the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "The bucket's ARN, for IAM policies and other ARN-based references."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket's global domain name (bucket.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket's region-specific domain name, useful when constructing S3 endpoints by hand."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "app_policy_arn" {
  description = "ARN of the standard read/write IAM policy for this bucket. Attach it to your application's IAM role. Null when create_app_policy is false."
  value       = var.create_app_policy ? aws_iam_policy.app_read_write[0].arn : null
}
