output "bucket_name" {
  description = "Name of the bucket. Put this in your application configuration / environment variables."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket, for referencing it from IAM policies or other resources."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional hostname of the bucket (e.g. <bucket>.s3.<region>.amazonaws.com), for use as a CloudFront origin or when constructing direct URLs."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the bucket when encryption = \"SSE-KMS\" (created by this module unless you supplied one). null when the bucket uses S3-managed encryption (SSE-S3)."
  value       = local.uses_kms ? local.kms_key_arn : null
}

output "app_access_policy_arn" {
  description = "ARN of the ready-made application access policy (see create_app_access_policy). null unless that option is enabled."
  value       = var.create_app_access_policy ? aws_iam_policy.app_access[0].arn : null
}
