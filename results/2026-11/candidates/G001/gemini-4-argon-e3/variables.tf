variable "application" {
  description = "Name of the application owning this bucket (lowercase alphanumeric and hyphens, e.g., 'checkout-service')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.application)) && !can(regex("--", var.application))
    error_message = "Application name must be 3-32 characters, lowercase alphanumeric and hyphens only, and cannot start/end with a hyphen or contain consecutive hyphens."
  }
}

variable "environment" {
  description = "Deployment environment for the application (e.g., 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "uat", "prod", "production", "sandbox"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, uat, prod, production, sandbox."
  }
}

variable "purpose" {
  description = "Short descriptor for what assets this bucket stores (e.g., 'assets', 'uploads', 'media', 'exports', 'logs')."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,18}[a-z0-9]$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "Purpose must be 2-20 characters, lowercase alphanumeric and hyphens only, and cannot start/end with a hyphen or contain consecutive hyphens."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for server-side encryption. When null, AES256 (SSE-S3) is used by default."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN (not an alias) or null."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning to protect against accidental overwrites and deletions."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions are permanently deleted."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && var.noncurrent_version_expiration_days <= 3650
    error_message = "noncurrent_version_expiration_days must be between 1 and 3650."
  }
}

variable "noncurrent_version_transition_ia_days" {
  description = "Number of days after which noncurrent object versions transition to STANDARD_IA. Must be at least 30 days and less than noncurrent_version_expiration_days."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_transition_ia_days >= 30
    error_message = "S3 requires at least 30 days before transitioning objects to STANDARD_IA."
  }
}

variable "enable_intelligent_tiering" {
  description = "Automatically transition current objects to Intelligent-Tiering to optimize storage costs for variable access patterns."
  type        = bool
  default     = true
}

variable "intelligent_tiering_transition_days" {
  description = "Days after creation before current objects transition to S3 Intelligent-Tiering."
  type        = number
  default     = 30

  validation {
    condition     = var.intelligent_tiering_transition_days >= 0
    error_message = "intelligent_tiering_transition_days must be >= 0."
  }
}

variable "expiration_days" {
  description = "Optional number of days after which current objects expire automatically (useful for temporary exports or logs). Leave null to retain objects indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || var.expiration_days >= 1
    error_message = "expiration_days must be null or a positive integer (>= 1)."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which incomplete multipart uploads are automatically aborted and cleaned up."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365
    error_message = "abort_incomplete_multipart_upload_days must be between 1 and 365."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-direct uploads or asset fetches (e.g., presigned URLs from a web frontend)."
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = optional(list(string), ["GET", "HEAD"])
    allowed_headers = optional(list(string), ["*"])
    expose_headers  = optional(list(string), ["ETag"])
    max_age_seconds = optional(number, 3600)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_origins) > 0 &&
      alltrue([for m in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    ])
    error_message = "Each CORS rule must specify at least one allowed_origin and valid HTTP methods (GET, PUT, POST, DELETE, HEAD)."
  }
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. Automatically disallowed in 'prod'/'production' unless explicitly set, recommended only for ephemeral dev/test environments."
  type        = bool
  default     = false
}

variable "access_log_bucket_name" {
  description = "Optional target S3 bucket name for server access logs. When provided, server access logs are delivered under the prefix '<application>/<environment>/<purpose>/'."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to merge with standard application and environment tags."
  type        = map(string)
  default     = {}
}
