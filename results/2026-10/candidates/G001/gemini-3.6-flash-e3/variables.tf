variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket to create for application assets."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A map of tags to assign to all resources created by this module."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Whether to allow OpenTofu to destroy the bucket even if it contains objects."
}

# --- Security & Public Access ---

variable "block_public_access" {
  type        = bool
  default     = true
  description = "Whether to block all public access (ACLs and policies) to the bucket."
}

variable "object_ownership" {
  type        = string
  default     = "BucketOwnerEnforced"
  description = "S3 Object Ownership setting. Options: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be one of: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  }
}

variable "enforce_ssl" {
  type        = bool
  default     = true
  description = "Whether to enforce TLS/HTTPS requests via bucket policy by denying unencrypted (HTTP) transport."
}

# --- Encryption ---

variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption algorithm to use. Options: AES256, aws:kms."
  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either 'AES256' or 'aws:kms'."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Existing KMS Key ARN to use for server-side encryption when sse_algorithm is aws:kms."
}

variable "create_kms_key" {
  type        = bool
  default     = false
  description = "Whether to create a dedicated KMS Customer Managed Key (CMK) for this bucket when sse_algorithm is aws:kms."
}

variable "kms_key_deletion_window_in_days" {
  type        = number
  default     = 30
  description = "Deletion window in days for the created KMS key (7 to 30 days)."
}

variable "bucket_key_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable S3 Bucket Key for SSE-KMS to lower KMS request costs."
}

# --- Versioning ---

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable object versioning to protect against accidental deletion and overwrites."
}

# --- Lifecycle Management ---

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  default     = 7
  description = "Days after which incomplete multipart uploads are automatically aborted (0 to disable)."
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Days after which noncurrent object versions are deleted (null to disable)."
}

variable "noncurrent_version_transitions" {
  type = list(object({
    days          = number
    storage_class = string
  }))
  default     = []
  description = "List of transition rules for noncurrent object versions (e.g., STANDARD_IA, GLACIER)."
}

variable "expiration_days" {
  type        = number
  default     = null
  description = "Days after which current objects expire and are deleted (null to disable)."
}

variable "transitions" {
  type = list(object({
    days          = number
    storage_class = string
  }))
  default     = []
  description = "List of transition rules for current objects (e.g., STANDARD_IA, GLACIER, DEEP_ARCHIVE)."
}

variable "custom_lifecycle_rules" {
  type        = list(any)
  default     = []
  description = "List of custom lifecycle rules for specific prefixes or tags."
}

# --- CORS (Cross-Origin Resource Sharing) ---

variable "cors_rules" {
  type = list(object({
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default     = []
  description = "List of CORS rules for direct browser access or cross-origin client uploads."
}

# --- Logging & Event Notifications ---

variable "logging_target_bucket" {
  type        = string
  default     = null
  description = "Target S3 bucket for storing server access logs. Disables logging if null."
}

variable "logging_target_prefix" {
  type        = string
  default     = "logs/"
  description = "Prefix for server access logs sent to target bucket."
}

variable "enable_eventbridge" {
  type        = bool
  default     = false
  description = "Whether to enable Amazon EventBridge notifications for S3 bucket events."
}

# --- Transfer Acceleration ---

variable "transfer_acceleration_enabled" {
  type        = bool
  default     = false
  description = "Whether to enable S3 Transfer Acceleration for faster global uploads."
}

# --- Custom IAM Policy Statements ---

variable "custom_policy_statements" {
  type        = list(any)
  default     = []
  description = "List of additional IAM policy statement objects to attach to the bucket policy."
}
