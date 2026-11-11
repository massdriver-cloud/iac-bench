output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket (<bucket>.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "app_access_policy_json" {
  description = "JSON IAM policy document granting read/write access to this bucket. Attach it to your application's IAM role."
  value       = data.aws_iam_policy_document.app_rw.json
}
