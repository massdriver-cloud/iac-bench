###############################################################################
#
# Outputs: everything an application team should need to consume the bucket.
#
###############################################################################

output "bucket_name" {
  description = "The real name of the bucket, e.g. \"checkout-uploads-123456789012-us-west-2\". Use this (not the name input) in application configuration, the AWS console and the CLI."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket itself, for IAM policies that act on the bucket as a whole (e.g. s3:ListBucket, s3:GetBucketLocation)."
  value       = aws_s3_bucket.this.arn
}

output "bucket_objects_arn" {
  description = "ARN of the objects in the bucket (\"<bucket-arn>/*\"), for IAM policies that act on object contents (s3:GetObject, s3:PutObject, ...)."
  value       = "${aws_s3_bucket.this.arn}/*"
}

output "bucket_domain_name" {
  description = "The global virtual-hosted-style domain of the bucket (\"<bucket>.s3.amazonaws.com\"). Prefer bucket_regional_domain_name unless you specifically need the global endpoint."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The regional virtual-hosted-style domain of the bucket (\"<bucket>.s3.<region>.amazonaws.com\"). Use this one when building URLs for presigned requests or pointing CloudFront at the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
