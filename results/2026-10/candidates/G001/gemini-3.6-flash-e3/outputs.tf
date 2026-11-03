output "bucket_id" {
  description = "The name (id) of the S3 bucket."
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
  description = "The bucket regional domain name (e.g. bucketname.s3.us-west-2.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "bucket_region" {
  description = "The AWS region this bucket is located in."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for bucket encryption (if created or specified)."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "The ID of the KMS key created by this module (if create_kms_key was true)."
  value       = try(aws_kms_key.this[0].key_id, null)
}
