output "bucket_name" {
  description = "Name of the bucket. This is the value your application's configuration needs."
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
  description = "Regional domain name of the bucket. Use this as the origin domain when putting CloudFront in front of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the bucket."
  value       = local.kms_key_arn
}

output "kms_key_alias" {
  description = "Alias of the module-managed KMS key (null when you supplied your own key)."
  value       = local.create_kms_key ? aws_kms_alias.this[0].name : null
}

output "access_log_bucket_name" {
  description = "Name of the bucket that receives this bucket's access logs."
  value       = local.access_log_bucket_name
}

output "access_log_prefix" {
  description = "Key prefix under which this bucket's access logs are written in the log bucket."
  value       = aws_s3_bucket_logging.this.target_prefix
}

output "read_write_policy_json" {
  description = "Least-privilege IAM policy (JSON) granting list/read/upload/delete on this bucket, including the required KMS permissions. Attach it to principals not covered by read_write_role_names."
  value       = data.aws_iam_policy_document.read_write.json
}

output "read_only_policy_json" {
  description = "Least-privilege IAM policy (JSON) granting list/read on this bucket, including the required KMS permission. Attach it to principals not covered by read_only_role_names."
  value       = data.aws_iam_policy_document.read_only.json
}
