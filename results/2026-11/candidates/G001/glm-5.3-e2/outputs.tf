output "bucket_name" {
  description = "Name of the bucket (which is also its S3 bucket ID)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket, e.g. for referencing in IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region the bucket lives in."
  value       = var.aws_region
}

output "bucket_domain_name" {
  description = "Global virtual-hosted-style domain of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional virtual-hosted-style domain of the bucket - the hostname to use for CDN origins and presigned URLs."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "KMS key used for server-side encryption, or null when SSE-S3 is in use."
  value       = local.kms_key_id
}

output "app_access_policy_json" {
  description = "Ready-to-attach IAM policy document (JSON) granting an application role read/write access to this bucket, and use of its KMS key when SSE-KMS is enabled. Attach it to your role with aws_iam_role_policy, or use read_write_principals instead and ignore this output."
  value       = data.aws_iam_policy_document.app_access.json
}

output "bucket_policy_json" {
  description = "The bucket policy this module manages (HTTPS enforcement plus any principal grants), for reference and debugging."
  value       = data.aws_iam_policy_document.bucket_policy.json
}
