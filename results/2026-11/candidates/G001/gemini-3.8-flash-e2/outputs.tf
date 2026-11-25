output "bucket_id" {
  description = "The name / ID of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket
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
  description = "The regional bucket domain name (e.g. bucketname.s3.us-east-1.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket."
  value       = var.versioning_enabled
}

output "encryption_algorithm" {
  description = "The server-side encryption algorithm configured on the bucket (AES256 or aws:kms)."
  value       = var.kms_key_arn != null ? "aws:kms" : "AES256"
}

output "kms_key_arn" {
  description = "The KMS key ARN used for SSE-KMS encryption (null if SSE-S3 is used)."
  value       = var.kms_key_arn
}

# --- Application IAM Policy Document Outputs ---

output "read_only_policy_json" {
  description = "JSON-encoded IAM policy document granting read-only access (ListBucket, GetObject) to the bucket and its objects."
  value       = data.aws_iam_policy_document.read_only.json
}

output "read_write_policy_json" {
  description = "JSON-encoded IAM policy document granting read/write access (ListBucket, GetObject, PutObject, DeleteObject) to the bucket and its objects."
  value       = data.aws_iam_policy_document.read_write.json
}

output "write_only_policy_json" {
  description = "JSON-encoded IAM policy document granting write-only / ingest access (PutObject, MultipartUpload) to the bucket."
  value       = data.aws_iam_policy_document.write_only.json
}

# --- Managed IAM Policy ARNs ---

output "read_only_policy_arn" {
  description = "ARN of the managed read-only IAM policy (null if create_iam_access_policies is false)."
  value       = try(aws_iam_policy.read_only[0].arn, null)
}

output "read_write_policy_arn" {
  description = "ARN of the managed read-write IAM policy (null if create_iam_access_policies is false)."
  value       = try(aws_iam_policy.read_write[0].arn, null)
}

output "write_only_policy_arn" {
  description = "ARN of the managed write-only IAM policy (null if create_iam_access_policies is false)."
  value       = try(aws_iam_policy.write_only[0].arn, null)
}
