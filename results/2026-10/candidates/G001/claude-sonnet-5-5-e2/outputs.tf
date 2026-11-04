output "bucket_name" {
  description = "Name of the bucket (use this in application config)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "read_write_policy_json" {
  description = "IAM policy JSON granting read/write/delete access to objects; attach to your application's role."
  value       = data.aws_iam_policy_document.read_write.json
}

output "read_only_policy_json" {
  description = "IAM policy JSON granting read-only access to objects; attach to consumers' roles."
  value       = data.aws_iam_policy_document.read_only.json
}
