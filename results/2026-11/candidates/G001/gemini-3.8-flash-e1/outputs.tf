################################################################################
# Outputs
################################################################################

output "bucket_id" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "The name of the S3 bucket (convenience alias for bucket_id)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (e.g. bucketname.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket regional domain name (e.g. bucketname.s3.us-east-1.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "The AWS region where the bucket resides."
  value       = aws_s3_bucket.this.region
}

output "read_only_policy_json" {
  description = "JSON document for an IAM policy granting read-only access to this bucket. Ready to attach to an IAM role or user."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "JSON document for an IAM policy granting read-write access to this bucket. Ready to attach to an IAM role or user."
  value       = data.aws_iam_policy_document.read_write.json
}

output "write_only_policy_json" {
  description = "JSON document for an IAM policy granting write-only (upload/ingest) access to this bucket. Ready to attach to an IAM role or user."
  value       = data.aws_iam_policy_document.write_only.json
}

output "read_only_policy_arn" {
  description = "The ARN of the created read-only IAM policy (if create_iam_policies is enabled)."
  value       = try(aws_iam_policy.read_only[0].arn, null)
}

output "read_write_policy_arn" {
  description = "The ARN of the created read-write IAM policy (if create_iam_policies is enabled)."
  value       = try(aws_iam_policy.read_write[0].arn, null)
}
