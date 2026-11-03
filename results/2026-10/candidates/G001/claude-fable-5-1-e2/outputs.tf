output "bucket_name" {
  description = "Name of the bucket. Put this in your application's configuration."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (e.g. for a CloudFront origin)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = local.region
}

output "read_write_policy_arn" {
  description = "ARN of the IAM managed policy granting read/write access to the bucket. Attach it to your application's role. Null if create_access_policies is false."
  value       = try(aws_iam_policy.read_write[0].arn, null)
}

output "read_only_policy_arn" {
  description = "ARN of the IAM managed policy granting read-only access to the bucket. Null if create_access_policies is false."
  value       = try(aws_iam_policy.read_only[0].arn, null)
}

output "read_write_policy_json" {
  description = "The read/write IAM policy as a JSON document, for teams that manage their own inline policies."
  value       = data.aws_iam_policy_document.read_write.json
}

output "read_only_policy_json" {
  description = "The read-only IAM policy as a JSON document, for teams that manage their own inline policies."
  value       = data.aws_iam_policy_document.read_only.json
}

output "encryption" {
  description = "How objects are encrypted at rest: \"SSE-S3\" or \"SSE-KMS\" (with the key ARN)."
  value = {
    type        = local.use_kms ? "SSE-KMS" : "SSE-S3"
    kms_key_arn = var.kms_key_arn
  }
}
