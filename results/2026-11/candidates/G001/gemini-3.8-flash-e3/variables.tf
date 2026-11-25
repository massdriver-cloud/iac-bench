variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket. Must be globally unique across all AWS accounts and follow S3 naming conventions."
}

variable "bucket" {
  type        = string
  description = "Alternative alias for bucket_name. If specified, overrides bucket_name."
  default     = null
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., 'production', 'staging', 'dev'). Used for resource tagging."
  default     = "production"
}

variable "application" {
  type        = string
  description = "Name of the application or service owning this bucket. Used for resource tagging."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources created by this module."
  default     = {}
}

variable "force_destroy" {
  type        = bool
  description = "Whether all objects should be deleted from the bucket so that the bucket can be destroyed without error. Defaults to false for safety."
  default     = false
}

variable "versioning_enabled" {
  type        = bool
  description = "Whether versioning is enabled to protect assets against accidental overwrites and deletions. Defaults to true."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of an AWS KMS key for server-side encryption. If omitted, default Amazon S3 managed keys (SSE-S3 / AES256) are used."
  default     = null
}

variable "bucket_key_enabled" {
  type        = bool
  description = "Whether to enable S3 Bucket Keys for SSE-KMS, reducing KMS request traffic and costs by up to 99%. Defaults to true."
  default     = true
}

variable "block_public_access" {
  type        = bool
  description = "Whether to enable all S3 Block Public Access settings (block public ACLs, block public policy, ignore public ACLs, restrict public buckets). Defaults to true."
  default     = true
}

variable "object_ownership" {
  type        = string
  description = "Object ownership setting. Defaults to 'BucketOwnerEnforced' (ACLs disabled), AWS's recommended best practice."
  default     = "BucketOwnerEnforced"
}

variable "enforce_tls" {
  type        = bool
  description = "Whether to enforce TLS/HTTPS on all bucket operations via bucket policy, denying insecure plaintext HTTP traffic. Defaults to true."
  default     = true
}

variable "minimum_tls_version" {
  type        = string
  description = "Minimum TLS version required for all bucket operations. Set to null to skip TLS version enforcement. Defaults to '1.2'."
  default     = "1.2"
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  description = "Number of days after initiation to automatically abort incomplete multipart uploads, preventing storage cost buildup on failed uploads. Defaults to 7."
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Number of days before non-current (overwritten or deleted) versions are permanently removed. Set to null to retain noncurrent versions indefinitely. Defaults to 90."
  default     = 90
}

variable "noncurrent_version_transition_days" {
  type        = number
  description = "Number of days before non-current versions transition to cheaper storage (e.g. STANDARD_IA). Set to null to disable transition. Defaults to null."
  default     = null
}

variable "noncurrent_version_transition_storage_class" {
  type        = string
  description = "Storage class for non-current version transitions. Defaults to 'STANDARD_IA'."
  default     = "STANDARD_IA"
}

variable "clean_expired_object_delete_markers" {
  type        = bool
  description = "Whether to remove expired object delete markers when all non-current versions are gone. Defaults to true."
  default     = true
}

variable "expiration_days" {
  type        = number
  description = "Number of days before current objects in the bucket are automatically deleted. Useful for logs or temporary generated assets. Set to null to retain objects indefinitely. Defaults to null."
  default     = null
}

variable "transition_days" {
  type        = number
  description = "Number of days before current objects transition to another storage class (e.g., STANDARD_IA or INTELLIGENT_TIERING). Set to null to disable transition. Defaults to null."
  default     = null
}

variable "transition_storage_class" {
  type        = string
  description = "Storage class for current object transitions. Defaults to 'STANDARD_IA'."
  default     = "STANDARD_IA"
}

variable "enable_intelligent_tiering" {
  type        = bool
  description = "Whether to enable S3 Intelligent-Tiering Archive and Deep Archive tiering. Defaults to false."
  default     = false
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "List of origin domains allowed to make CORS requests to the bucket (e.g., ['https://app.example.com']). If empty, no default CORS configuration is created."
  default     = []
}

variable "cors_allowed_methods" {
  type        = list(string)
  description = "List of HTTP methods allowed for CORS requests. Defaults to ['GET', 'HEAD', 'PUT', 'POST', 'DELETE']."
  default     = ["GET", "HEAD", "PUT", "POST", "DELETE"]
}

variable "cors_allowed_headers" {
  type        = list(string)
  description = "List of HTTP headers allowed in CORS requests. Defaults to ['*']."
  default     = ["*"]
}

variable "cors_expose_headers" {
  type        = list(string)
  description = "List of HTTP headers exposed to browsers in CORS responses. Defaults to ['ETag']."
  default     = ["ETag"]
}

variable "cors_max_age_seconds" {
  type        = number
  description = "Time in seconds that browsers can cache CORS preflight responses. Defaults to 3600 (1 hour)."
  default     = 3600
}

variable "cors_rules" {
  type        = any
  description = "Advanced: List of custom CORS rule maps. If non-empty, overrides cors_allowed_origins configuration."
  default     = []
}

variable "custom_lifecycle_rules" {
  type        = any
  description = "Advanced: List of additional custom lifecycle rules to apply to the bucket."
  default     = []
}

variable "logging_target_bucket" {
  type        = string
  description = "Target S3 bucket name for S3 server access logging. If null, server access logging is disabled. Defaults to null."
  default     = null
}

variable "logging_target_prefix" {
  type        = string
  description = "Prefix for server access log objects. Defaults to 's3-access-logs/<bucket_name>/' if logging_target_bucket is provided."
  default     = null
}

variable "read_only_principals" {
  type        = list(string)
  description = "List of IAM principal ARNs (roles, users, etc.) granted read-only access (s3:GetObject, s3:ListBucket) via bucket policy."
  default     = []
}

variable "read_write_principals" {
  type        = list(string)
  description = "List of IAM principal ARNs (roles, users, etc.) granted read-write access (s3:GetObject, s3:PutObject, s3:DeleteObject, s3:ListBucket) via bucket policy."
  default     = []
}

variable "cloudfront_distribution_arns" {
  type        = list(string)
  description = "List of CloudFront distribution ARNs granted read access via Origin Access Control (OAC)."
  default     = []
}

variable "custom_policy_json" {
  type        = string
  description = "Optional raw IAM bucket policy JSON string to merge with the module's generated policy."
  default     = null
}

variable "custom_policy_documents" {
  type        = list(string)
  description = "Optional list of IAM policy JSON documents to merge with the module's generated policy."
  default     = []
}
