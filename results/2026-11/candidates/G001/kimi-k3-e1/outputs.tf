output "bucket_name" {
  description = "Name of the bucket. This is what your application puts in its config (SDK clients take the bare name)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket. Use this in IAM policies to grant your application's role access (object ARNs are \"<bucket_arn>/*\")."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket (<name>.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket. Use this (not the global one) as a CloudFront origin or HTTPS endpoint."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket (echoes the module input so callers can wire dependent logic)."
  value       = var.versioning_enabled
}
