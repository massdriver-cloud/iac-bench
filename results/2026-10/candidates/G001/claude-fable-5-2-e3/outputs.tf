output "bucket_name" {
  description = "Name of the bucket. This is what your application's S3 client needs."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = local.region
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket. Use this as the origin domain when putting CloudFront in front of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the bucket's objects."
  value       = local.kms_key_arn
}

output "read_only_policy_arn" {
  description = "Attach this IAM policy to a role that only needs to list and read objects. Null when create_iam_policies is false."
  value       = one(aws_iam_policy.read_only[*].arn)
}

output "read_write_policy_arn" {
  description = "Attach this IAM policy to your application's role to let it list, read, write and delete objects. Null when create_iam_policies is false."
  value       = one(aws_iam_policy.read_write[*].arn)
}

output "read_only_policy_json" {
  description = "The read-only policy as JSON, for use as an inline policy."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "The read-write policy as JSON, for use as an inline policy."
  value       = data.aws_iam_policy_document.read_write.json
}

output "access_log_bucket_name" {
  description = "Bucket that receives this bucket's server access logs."
  value       = local.log_bucket_name
}

output "access_log_prefix" {
  description = "Key prefix under which this bucket's access logs are written."
  value       = local.log_prefix
}
