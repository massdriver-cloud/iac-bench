output "bucket_name" {
  description = "Name of the bucket. Use this in your application configuration."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use this when writing IAM policies for your application."
  value       = aws_s3_bucket.this.arn
}

output "bucket_objects_arn" {
  description = "ARN pattern matching every object in the bucket (\"<bucket arn>/*\"), for IAM object-level permissions."
  value       = "${aws_s3_bucket.this.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket, e.g. for a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "KMS key used for encryption, or null when using S3-managed keys."
  value       = var.kms_key_arn
}
