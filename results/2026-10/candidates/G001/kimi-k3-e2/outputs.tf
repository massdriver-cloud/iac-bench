output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket — this is what you reference in IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_uri" {
  description = "s3:// URI of the bucket, handy for CLI scripts and app config."
  value       = "s3://${aws_s3_bucket.this.bucket}"
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (e.g. for a CDN origin or endpoint config)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "AWS region the bucket lives in."
  value       = aws_s3_bucket.this.region
}
