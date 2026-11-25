output "bucket_name" {
  description = "Bucket name to pass to the S3 SDK."
  value       = aws_s3_bucket.assets.id
}

output "bucket_region" {
  description = "AWS region to use for the S3 client."
  value       = aws_s3_bucket.assets.region
}

output "bucket_arn" {
  description = "Bucket ARN for bucket-level IAM permissions such as s3:ListBucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_objects_arn" {
  description = "Wildcard object ARN for object-level IAM permissions. Scope it to an application prefix when appropriate."
  value       = "${aws_s3_bucket.assets.arn}/*"
}

output "bucket_regional_domain_name" {
  description = "Regional S3 hostname, not a public website or an access grant."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
