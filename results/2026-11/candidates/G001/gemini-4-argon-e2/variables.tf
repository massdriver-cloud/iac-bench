variable "application_name" {
  description = "Name of the application that owns this bucket (lowercase alphanumeric and hyphens, e.g. 'billing-service')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}[a-z0-9]$", var.application_name))
    error_message = "application_name must be 3-42 characters, lowercase alphanumeric and hyphens, and start/end with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment for the application (e.g. 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = contains(["dev", "test", "qa", "staging", "preprod", "prod", "production", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, test, qa, staging, preprod, prod, production, sandbox."
  }
}

variable "purpose" {
  description = "Short descriptor for what assets this bucket holds (e.g. 'assets', 'uploads', 'media', 'exports', 'logs')."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,20}[a-z0-9]$", var.purpose))
    error_message = "purpose must be 2-22 characters, lowercase alphanumeric and hyphens."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit bucket name override. When null, a globally unique, standardized bucket name (<application_name>-<environment>-<purpose>-<account_id>-<region>) is generated automatically."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name_override == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name_override))
    error_message = "bucket_name_override must be a valid DNS-compliant S3 bucket name (3-63 characters, lowercase letters, numbers, dots, and hyphens)."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used for SSE-KMS encryption. When null (the default), SSE-S3 (AES256) default encryption is used so application IAM roles do not need extra KMS key grants."
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Whether to keep object version history to protect against accidental overwrites and deletions."
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain overwritten or deleted (noncurrent) object versions before permanently expiring them."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 1 and 3650 days."
  }
}

variable "noncurrent_versions_to_retain" {
  description = "Maximum number of newer noncurrent object versions to retain unconditionally before age-based expiration applies."
  type        = number
  default     = 3

  validation {
    condition     = var.noncurrent_versions_to_retain >= 0 && var.noncurrent_versions_to_retain <= 100
    error_message = "noncurrent_versions_to_retain must be between 0 and 100."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which abandoned/incomplete multipart uploads are automatically cleaned up to prevent orphaned storage charges."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365
    error_message = "abort_incomplete_multipart_upload_days must be between 1 and 365 days."
  }
}

variable "enable_intelligent_tiering" {
  description = "Automatically transition objects to S3 Intelligent-Tiering after intelligent_tiering_transition_days to optimize storage costs for variable access patterns."
  type        = bool
  default     = true
}

variable "intelligent_tiering_transition_days" {
  description = "Days after creation before objects transition to S3 Intelligent-Tiering (0 transitions immediately/at next daily sweep)."
  type        = number
  default     = 30

  validation {
    condition     = var.intelligent_tiering_transition_days >= 0 && var.intelligent_tiering_transition_days <= 3650
    error_message = "intelligent_tiering_transition_days must be between 0 and 3650."
  }
}

variable "object_expiration_days" {
  description = "Optional number of days after which current objects expire automatically (useful for ephemeral files, exports, or application logs). Set to null to retain current objects indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || var.object_expiration_days >= 1
    error_message = "object_expiration_days must be null or at least 1 day."
  }
}

variable "cors_allowed_origins" {
  description = "Optional list of web origins (e.g. ['https://app.example.com']) allowed to make browser CORS requests (such as direct presigned PUT/GET uploads). When empty, no CORS configuration is attached."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for browser CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods may only contain GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cors_allowed_headers" {
  description = "HTTP headers allowed in browser CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "HTTP response headers exposed to browsers in CORS responses."
  type        = list(string)
  default     = ["ETag", "x-amz-request-id", "x-amz-id-2"]
}

variable "cors_max_age_seconds" {
  description = "Time in seconds that a browser can cache the preflight OPTIONS response."
  type        = number
  default     = 3600
}

variable "access_log_bucket_name" {
  description = "Optional target S3 bucket name for server access logs. When provided, server access logs are delivered under prefix '<application_name>/<environment>/<bucket_name>/'."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. If null, defaults to false in prod/production/preprod environments and true in non-production environments."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Additional tags to merge with standard application and environment tags."
  type        = map(string)
  default     = {}
}
