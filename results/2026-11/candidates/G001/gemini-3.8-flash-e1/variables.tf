################################################################################
# Core Bucket Configuration
################################################################################

variable "bucket_name" {
  description = "The globally unique name of the S3 bucket. Must follow standard S3 bucket naming conventions (lowercase letters, numbers, hyphens, 3-63 characters)."
  type        = string

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    error_message = "The bucket_name must be between 3 and 63 characters long, begin and end with a lowercase letter or number, and contain only lowercase letters, numbers, hyphens, and dots."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. 'production', 'staging', 'dev'). Automatically tagged on all resources."
  type        = string
  default     = "production"
}

variable "application" {
  description = "Name of the application or service using this bucket (e.g. 'user-service', 'billing-api'). Automatically tagged on all resources."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional custom tags to merge with the standard tags."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Whether to allow OpenTofu to delete the bucket even if it contains objects. Recommended false for production; can be set to true for ephemeral test/dev environments."
  type        = bool
  default     = false
}

################################################################################
# Security & Access Control
################################################################################

variable "block_public_access" {
  description = "Whether to block all public access (ACLs and policies). Application asset buckets are private by default."
  type        = bool
  default     = true
}

variable "enforce_tls" {
  description = "Whether to enforce TLS/HTTPS only on all requests by denying unencrypted HTTP transport."
  type        = bool
  default     = true
}

variable "object_ownership" {
  description = "S3 Object Ownership setting. 'BucketOwnerEnforced' disables ACLs and ensures the bucket owner owns all objects."
  type        = string
  default     = "BucketOwnerEnforced"
  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be one of: 'BucketOwnerEnforced', 'BucketOwnerPreferred', 'ObjectWriter'."
  }
}

variable "custom_bucket_policy" {
  description = "Additional IAM bucket policy JSON statement(s) to attach to the bucket in addition to the TLS enforcement policy."
  type        = string
  default     = null
}

################################################################################
# Encryption
################################################################################

variable "sse_algorithm" {
  description = "Server-side encryption algorithm to use. Defaults to AES256. Use 'aws:kms' if using KMS keys."
  type        = string
  default     = "AES256"
  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either 'AES256' or 'aws:kms'."
  }
}

variable "kms_key_arn" {
  description = "The ARN of a customer-managed KMS key to use for SSE-KMS encryption. If provided, sse_algorithm automatically uses aws:kms."
  type        = string
  default     = null
}

variable "bucket_key_enabled" {
  description = "Whether to use Amazon S3 Bucket Keys for SSE-KMS. Reduces KMS request traffic and costs by up to 99%."
  type        = bool
  default     = true
}

################################################################################
# Versioning
################################################################################

variable "versioning_enabled" {
  description = "Whether to enable S3 versioning to protect application assets against accidental deletion and overwrites."
  type        = bool
  default     = true
}

################################################################################
# Lifecycle Management
################################################################################

variable "enable_lifecycle_rules" {
  description = "Whether to enable automated lifecycle rules for cost optimization and storage cleanup."
  type        = bool
  default     = true
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after initiation to abort incomplete multipart uploads, preventing hidden storage costs from abandoned uploads."
  type        = number
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent (previous) object versions are permanently deleted. Set to null to retain noncurrent versions indefinitely."
  type        = number
  default     = 90
}

variable "noncurrent_version_transition_days" {
  description = "Number of days after which noncurrent (previous) object versions are transitioned to STANDARD_IA. Set to null to disable transition."
  type        = number
  default     = 30
}

variable "transition_to_intelligent_tiering_days" {
  description = "Number of days after creation to transition current objects to INTELLIGENT_TIERING storage class. Set to null to disable."
  type        = number
  default     = null
}

variable "transition_to_ia_days" {
  description = "Number of days after creation to transition current objects to STANDARD_IA storage class. Set to null to disable."
  type        = number
  default     = null
}

variable "transition_to_glacier_days" {
  description = "Number of days after creation to transition current objects to GLACIER storage class. Set to null to disable."
  type        = number
  default     = null
}

variable "expiration_days" {
  description = "Number of days after creation to expire/delete current objects. Useful for transient generated assets, temporary exports, or logs."
  type        = number
  default     = null
}

################################################################################
# CORS (Cross-Origin Resource Sharing)
################################################################################

variable "cors_rules" {
  description = "List of CORS rules to allow browser-based direct uploads or asset fetching (e.g. presigned URLs, web media players)."
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3600)
  }))
  default = []
}

################################################################################
# Server Access Logging
################################################################################

variable "logging_target_bucket" {
  description = "The target S3 bucket name to deliver server access logs to. If null, server access logging is disabled."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "The key prefix for server access log objects. Defaults to 's3-access-logs/<bucket_name>/'."
  type        = string
  default     = null
}

################################################################################
# IAM Policies
################################################################################

variable "create_iam_policies" {
  description = "Whether to create managed IAM policy resources for read-only and read-write access to this bucket."
  type        = bool
  default     = false
}
