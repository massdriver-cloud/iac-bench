variable "app_name" {
  description = "Name of the application owning this bucket (lowercase alphanumeric and hyphens, e.g., 'checkout-service')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.app_name)) && !can(regex("--", var.app_name))
    error_message = "app_name must be 3-32 characters, contain only lowercase letters, numbers, and single hyphens, and start/end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "uat", "prod", "production", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, test, staging, uat, prod, production, sandbox."
  }
}

variable "purpose" {
  description = "Short descriptor for what assets this bucket stores (e.g., 'assets', 'uploads', 'media', 'exports', 'logs')."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}[a-z0-9]$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 3-22 characters, contain only lowercase letters, numbers, and single hyphens, and start/end with a letter or number."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit bucket name override. If null, a standard globally-unique name is generated from app_name, purpose, environment, account ID, and region."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name_override == null ? true : (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name_override)) && !can(regex("\\.\\.|--|^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.bucket_name_override)))
    error_message = "bucket_name_override must be a valid S3 bucket name (3-63 chars, lowercase alphanumeric, dots, or hyphens, not formatted as an IP address)."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for server-side encryption (SSE-KMS). Defaults to AWS-managed SSE-S3 (AES256) when null so app teams don't hit KMS permission errors by default."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws(-[a-z]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "enable_versioning" {
  description = "Keep object version history to protect against accidental overwrites and deletions."
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain noncurrent (overwritten/deleted) object versions before permanently expiring them."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 1 and 3650 days."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads are automatically cleaned up to prevent orphaned storage costs."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 30
    error_message = "abort_incomplete_multipart_upload_days must be between 1 and 30 days."
  }
}

variable "enable_intelligent_tiering" {
  description = "Automatically transition objects larger than 128KB into S3 Intelligent-Tiering after intelligent_tiering_transition_days to optimize storage costs."
  type        = bool
  default     = true
}

variable "intelligent_tiering_transition_days" {
  description = "Days after creation before objects transition to S3 Intelligent-Tiering."
  type        = number
  default     = 30

  validation {
    condition     = var.intelligent_tiering_transition_days >= 0 && var.intelligent_tiering_transition_days <= 365
    error_message = "intelligent_tiering_transition_days must be between 0 and 365."
  }
}

variable "object_expiration_days" {
  description = "Optional number of days after which current objects automatically expire (useful for temporary exports, logs, or scratch uploads). Leave null to keep objects indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null ? true : var.object_expiration_days >= 1
    error_message = "object_expiration_days must be at least 1 day when set."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for browser direct uploads/downloads (e.g., ['https://app.example.com']). Leave empty to disable CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : o != "*"])
    error_message = "Wildcard '*' is not allowed in cors_allowed_origins; specify explicit origins (e.g., 'https://app.example.com')."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods may only contain GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cors_allowed_headers" {
  description = "Headers allowed in preflight CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "Headers exposed to browser clients in CORS responses."
  type        = list(string)
  default     = ["ETag", "x-amz-request-id", "x-amz-id-2"]
}

variable "cors_max_age_seconds" {
  description = "Time in seconds that browsers can cache preflight OPTIONS responses."
  type        = number
  default     = 3600
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when not empty. Defaults to false for safety; only allowed in non-production environments when explicitly enabled."
  type        = bool
  default     = false

  validation {
    condition     = !(var.force_destroy && contains(["prod", "production"], var.environment))
    error_message = "force_destroy cannot be enabled when environment is 'prod' or 'production'."
  }
}

variable "logging_target_bucket" {
  description = "Optional S3 bucket name to receive server access logs for this bucket."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Optional key prefix for server access logs when logging_target_bucket is set. Defaults to '<bucket_name>/'."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to merge with standard module tags."
  type        = map(string)
  default     = {}
}
