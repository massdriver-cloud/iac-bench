output "bucket_name" {
  description = "Name of the bucket. Give this to your application (e.g. as an environment variable)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region the bucket lives in."
  value       = local.region
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket, e.g. for use as a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts objects in the bucket."
  value       = local.kms_key_arn
}

output "read_write_policy_arn" {
  description = "ARN of an IAM policy granting list/download/upload/delete on the bucket. Attach it to your application's role if you did not use read_write_role_names."
  value       = aws_iam_policy.read_write.arn
}

output "read_only_policy_arn" {
  description = "ARN of an IAM policy granting list/download on the bucket. Attach it to roles that only read, if you did not use read_only_role_names."
  value       = aws_iam_policy.read_only.arn
}

output "access_log_bucket_name" {
  description = "Name of the bucket receiving this bucket's server access logs."
  value       = local.log_target_bucket
}

output "access_log_prefix" {
  description = "Key prefix under which this bucket's access logs are written in the log bucket."
  value       = local.log_target_prefix
}
