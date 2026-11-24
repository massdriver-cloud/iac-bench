output "bucket_name" {
  description = "Name of the bucket. Put this in your application's configuration."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Regional DNS name of the bucket (<bucket>.s3.<region>.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "s3_uri" {
  description = "s3:// URI of the bucket, handy for CLI and job configuration."
  value       = "s3://${aws_s3_bucket.this.bucket}"
}

output "app_access_policy_json" {
  description = "Least-privilege read/write IAM policy for this bucket. Attach it to your application's role yourself, or pass the role ARNs via iam_role_arns and the module does it for you."
  value       = data.aws_iam_policy_document.app_access.json
}
