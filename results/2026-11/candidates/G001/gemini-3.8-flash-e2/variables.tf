variable "bucket_name" {
  description = "The name of the S3 bucket for application assets. Must be globally unique, between 3 and 63 characters, and contain only lowercase alphanumeric characters and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be between 3 and 63 characters, start and end with an alphanumeric character, and contain only lowercase letters, numbers, hyphens, and dots."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. 'production', 'staging', 'dev'). Automatically added to resource tags if provided."
  type        = string
  default     = null
}

variable "application" {
  description = "Name of the application or service owning this bucket. Automatically added to resource tags if provided."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to assign to the bucket and associated resources."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Whether to allow OpenTofu to destroy the bucket even if it contains objects. Default is false to prevent accidental loss of application data."
  type        = bool
  default     = false
}

# --- Security & Access Controls ---

variable "block_public_access" {
  description = "Whether to block all public access to the bucket. Modern application asset buckets must remain private by default."
  type        = bool
  default     = true
}

variable "object_ownership" {
  description = "Object ownership configuration. Defaults to 'BucketOwnerEnforced' which disables ACLs and guarantees the bucket owner owns all assets."
  type        = string
  default     = "BucketOwnerEnforced"
}

variable "enforce_tls" {
  description = "Whether to enforce TLS/HTTPS for all access to the bucket and deny plaintext HTTP requests."
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version required for requests when enforce_tls is true. Defaults to '1.2'."
  type        = string
  default     = "1.2"
}

variable "kms_key_arn" {
  description = "The ARN of a customer-managed KMS key to use for SSE-KMS encryption. If null, AES256 (SSE-S3) encryption is used at zero additional cost."
  type        = string
  default     = null
}

variable "bucket_key_enabled" {
  description = "Whether to enable S3 Bucket Key for server-side encryption. Reduces KMS request traffic and costs by up to 99%."
  type        = bool
  default     = true
}

variable "custom_bucket_policy" {
  description = "Optional JSON policy document to merge with the module's baseline security policies (e.g. for CloudFront OAC or cross-account access)."
  type        = string
  default     = null
}

# --- Durability & Versioning ---

variable "versioning_enabled" {
  description = "Whether to enable versioning for the bucket. Protects application assets against accidental overwrites and deletes."
  type        = bool
  default     = true
}

# --- Lifecycle & Cost Optimization ---

variable "lifecycle_rules_enabled" {
  description = "Whether to enable automated lifecycle rules to prevent runaway storage costs from abandoned multipart uploads and accumulated old versions."
  type        = bool
  default     = true
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which incomplete multipart uploads are aborted and cleaned up. Prevents hidden charges from failed file uploads."
  type        = number
  default     = 7
}

variable "clean_expired_delete_markers" {
  description = "Whether to automatically remove expired object delete markers when all versions have been deleted."
  type        = bool
  default     = true
}

variable "noncurrent_version_transition_days" {
  description = "Number of days before transitioning noncurrent object versions to Standard-IA storage. Set to null to disable transition."
  type        = number
  default     = 30
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days before expiring and permanently deleting noncurrent object versions. Set to null to retain noncurrent versions indefinitely."
  type        = number
  default     = 90
}

variable "noncurrent_version_retain_count" {
  description = "Minimum number of newer noncurrent versions to retain regardless of expiration days. Ensures safety against accidental overwrites."
  type        = number
  default     = 3
}

variable "current_version_transition_ia_days" {
  description = "Number of days before transitioning current objects to Standard-IA storage class. Defaults to null (no transition)."
  type        = number
  default     = null
}

variable "current_version_transition_glacier_days" {
  description = "Number of days before transitioning current objects to Glacier storage class. Defaults to null (no transition)."
  type        = number
  default     = null
}

variable "current_version_expiration_days" {
  description = "Number of days before expiring current objects. Useful for log archives, temporary exports, or scratch storage. Defaults to null."
  type        = number
  default     = null
}

variable "custom_lifecycle_rules" {
  description = "List of custom lifecycle rule configurations for prefix-specific or advanced retention requirements."
  type        = any
  default     = []
}

# --- Web & Cross-Origin ---

variable "cors_rules" {
  description = "List of CORS rules for the bucket. Essential for web applications uploading directly from browsers via presigned URLs or displaying assets cross-origin."
  type = list(object({
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), ["ETag"])
    max_age_seconds = optional(number, 3600)
  }))
  default = []
}

# --- Logging & Events ---

variable "logging_target_bucket" {
  description = "The name of the target bucket for S3 server access logging. If null, server access logging is disabled."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefix for server access logging. Defaults to 's3-access-logs/<bucket-name>/' if logging_target_bucket is provided."
  type        = string
  default     = null
}

variable "enable_eventbridge" {
  description = "Whether to enable Amazon EventBridge notifications for bucket events. Recommended for event-driven asset processing (e.g., image resizing, malware scanning)."
  type        = bool
  default     = false
}

# --- Application IAM Integration ---

variable "create_iam_access_policies" {
  description = "Whether to create managed IAM policy resources in AWS for read-only, read-write, and write-only application access. Regardless of this setting, the policy JSON documents are always exported as outputs."
  type        = bool
  default     = false
}

variable "iam_policy_name_prefix" {
  description = "Prefix for the managed IAM policies if create_iam_access_policies is enabled. Defaults to the bucket name."
  type        = string
  default     = null
}
