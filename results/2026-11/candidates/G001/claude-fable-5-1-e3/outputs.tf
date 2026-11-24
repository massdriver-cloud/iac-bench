output "bucket_name" {
  description = "Name of the bucket. Use this in your application config and IAM policies."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_objects_arn" {
  description = "ARN pattern matching every object in the bucket (handy for IAM policy resources)."
  value       = "${aws_s3_bucket.this.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket, e.g. for a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.this.region
}

output "encryption" {
  description = "Encryption in effect: 'SSE-S3' or 'SSE-KMS'."
  value       = local.use_kms ? "SSE-KMS" : "SSE-S3"
}

output "kms_key_arn" {
  description = "KMS key encrypting the bucket, if SSE-KMS is in use (null otherwise). Grant your application kms:Decrypt / kms:GenerateDataKey on it."
  value       = var.kms_key_arn
}
