output "bucket_id" {
  description = "The name of the bucket (same as bucket_name)."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (e.g., bucketname.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name (e.g., bucketname.s3.us-east-1.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "The AWS region this bucket resides in."
  value       = aws_s3_bucket.this.region
}

output "hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket."
  value       = var.versioning_enabled
}

output "policy_json" {
  description = "The JSON content of the bucket policy applied to the bucket, if configured."
  value       = local.create_bucket_policy ? data.aws_iam_policy_document.bucket_policy[0].json : null
}
