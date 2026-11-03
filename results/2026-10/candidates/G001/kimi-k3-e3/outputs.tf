output "bucket_name" {
  value       = aws_s3_bucket.this.id
  description = "Name of the bucket. Pass this to your application (e.g. as an env var) so it knows where its assets live."
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "ARN of the bucket. Use this (with /* appended for objects) in the IAM policy you give your application's role."
}

output "bucket_region" {
  value       = aws_s3_bucket.this.region
  description = "AWS region the bucket lives in. Many S3 clients need this explicitly."
}

output "bucket_regional_domain_name" {
  value       = aws_s3_bucket.this.bucket_regional_domain_name
  description = "Regional domain name of the bucket, for constructing object URLs or CloudFront origins."
}
