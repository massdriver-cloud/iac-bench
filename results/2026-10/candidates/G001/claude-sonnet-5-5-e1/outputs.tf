output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (for CloudFront origins or SDK endpoints)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "read_write_policy_json" {
  description = "IAM policy document JSON granting read/write/delete on objects and list on the bucket. Attach to your application's role."
  value       = data.aws_iam_policy_document.app_access.json
}

output "read_only_policy_json" {
  description = "IAM policy document JSON granting read-only access. Attach to consumers that only read."
  value       = data.aws_iam_policy_document.app_read.json
}
