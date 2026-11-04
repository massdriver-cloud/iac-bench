variable "region" {
  type        = string
  description = "AWS region where resources will be created."
  default     = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket. Must be globally unique."
}

variable "force_destroy" {
  type        = bool
  description = "Boolean indicating whether all objects should be deleted from the bucket when destroyed."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Map of tags to assign to the bucket."
  default     = {}
}

variable "versioning_enabled" {
  type        = bool
  description = "State of bucket versioning. Defaults to true for data protection."
  default     = true
}

variable "block_public_access" {
  type        = bool
  description = "Whether to block all public access to the S3 bucket."
  default     = true
}

variable "enable_tls_only_policy" {
  type        = bool
  description = "Whether to require HTTPS (TLS) for all requests to the bucket."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key to use for server-side encryption. If null, AES256 (SSE-S3) is used."
  default     = null
}

variable "bucket_key_enabled" {
  type        = bool
  description = "Whether to use S3 Bucket Keys for SSE-KMS."
  default     = true
}

variable "object_ownership" {
  type        = string
  description = "Object ownership control. Options: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  default     = "BucketOwnerEnforced"
  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be one of: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  description = "Number of days after which incomplete multipart uploads are automatically aborted. Set to null to disable."
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Number of days after which noncurrent object versions are expired. Set to null to disable."
  default     = 90
}

variable "cors_rules" {
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string))
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  description = "List of CORS rules for the bucket."
  default     = []
}

variable "logging" {
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  description = "Target bucket and prefix for S3 access logging."
  default     = null
}

variable "custom_policy_document_json" {
  type        = string
  description = "An optional JSON string representing a custom IAM policy document to apply to the bucket."
  default     = null
}

variable "custom_lifecycle_rules" {
  type = list(object({
    id                                 = string
    status                             = optional(string, "Enabled")
    prefix                             = optional(string)
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
  }))
  description = "List of custom lifecycle rules."
  default     = []
}
