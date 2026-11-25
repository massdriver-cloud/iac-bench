output "bucket_name" {
  description = "Name of the bucket. Use this in your application config and IAM policies."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Grant your app's IAM role s3:GetObject/s3:PutObject etc. on this ARN and \"<arn>/*\"."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional virtual-hosted-style endpoint (TLS-safe). Prefer this over bucket_domain_name for SDK/endpoint configuration."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_domain_name" {
  description = "Global virtual-hosted-style endpoint of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "s3_uri" {
  description = "s3:// URI of the bucket, handy for CLI and job configuration."
  value       = "s3://${aws_s3_bucket.this.id}"
}

output "aws_region" {
  description = "Region the bucket lives in."
  value       = var.aws_region
}

output "kms_key_arn" {
  description = "KMS key used for encryption, or null when using S3-managed encryption (AES256). If non-null, your app's IAM role needs kms:Decrypt and kms:GenerateDataKey on this key."
  value       = var.kms_key_arn
}
