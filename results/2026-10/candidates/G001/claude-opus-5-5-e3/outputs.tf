output "bucket_name" {
  description = "Name of the bucket. Give this to your application (e.g. as an env var)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (use as a CloudFront origin)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "read_write_policy_json" {
  description = "IAM policy JSON granting read/write access to objects in this bucket. Attach it to your application's IAM role."
  value       = data.aws_iam_policy_document.read_write.json
}

output "read_only_policy_json" {
  description = "IAM policy JSON granting read-only access to objects in this bucket."
  value       = data.aws_iam_policy_document.read_only.json
}
