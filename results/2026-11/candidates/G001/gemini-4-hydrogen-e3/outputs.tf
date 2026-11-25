output "bucket_name" {
  description = "Name (ID) of the provisioned S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the provisioned S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket (preferred for CloudFront origins and regional SDK endpoints)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_region" {
  description = "AWS region where the bucket was provisioned."
  value       = aws_s3_bucket.this.region
}

output "effective_configuration" {
  description = "Summary of the opinionated defaults applied to this bucket."
  value = {
    usage_profile             = var.usage_profile
    versioning_enabled        = local.effective_versioning_enabled
    encryption_algorithm      = var.kms_key_arn != null ? "aws:kms" : "AES256"
    kms_key_arn               = var.kms_key_arn
    expiration_days           = local.effective_expiration_days
    noncurrent_retention_days = local.effective_versioning_enabled ? local.effective_noncurrent_days : null
    multipart_abort_days      = local.profile.multipart_abort_days
    cors_enabled              = length(var.cors_allowed_origins) > 0
    eventbridge_enabled       = var.enable_eventbridge
    public_access_blocked     = true
    acls_disabled             = true
    https_enforced            = true
  }
}

output "read_only_policy_json" {
  description = "Ready-to-use least-privilege IAM policy JSON for applications that only read objects from this bucket."
  value       = data.aws_iam_policy_document.read_only.json
}

output "write_only_policy_json" {
  description = "Ready-to-use least-privilege IAM policy JSON for applications that only upload/write objects to this bucket."
  value       = data.aws_iam_policy_document.write_only.json
}

output "read_write_policy_json" {
  description = "Ready-to-use least-privilege IAM policy JSON for applications that read, write, and delete objects in this bucket."
  value       = data.aws_iam_policy_document.read_write.json
}

output "iam_policy_arns" {
  description = "ARNs of the created IAM policies when create_iam_policies is true; null values otherwise."
  value = {
    read_only  = var.create_iam_policies ? aws_iam_policy.read_only[0].arn : null
    write_only = var.create_iam_policies ? aws_iam_policy.write_only[0].arn : null
    read_write = var.create_iam_policies ? aws_iam_policy.read_write[0].arn : null
  }
}
