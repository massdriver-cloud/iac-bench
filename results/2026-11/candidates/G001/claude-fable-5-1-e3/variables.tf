############################################
# Required inputs — the only things an app team must provide
############################################

variable "application" {
  description = "Short name of the application that owns this bucket (lowercase letters, digits, hyphens). Used to build the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.application))
    error_message = "application must be 1-24 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. dev, test, staging, prod. Used to build the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,8}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-10 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

############################################
# Optional inputs — sensible defaults, override only if you know you need to
############################################

variable "region" {
  description = "AWS region to create the bucket in. Defaults to the region configured in the environment (AWS_REGION / profile)."
  type        = string
  default     = null
}

variable "bucket_name" {
  description = "Escape hatch: explicit bucket name. Leave null to use the generated name '<application>-<environment>-<account-id>-<region>', which is globally unique and self-describing."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens."
  }
}

variable "kms_key_arn" {
  description = "ARN of a customer-managed KMS key to encrypt objects with (SSE-KMS). Leave null to use S3-managed encryption (SSE-S3), which is free and sufficient for most application assets."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "Origins allowed to make cross-origin requests (e.g. [\"https://app.example.com\"]). Set this when browsers upload to or fetch from the bucket directly. Empty disables CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : o != "*"])
    error_message = "Wildcard '*' origins are not allowed; list the exact origins your application is served from."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests. Only used when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods may only contain GET, HEAD, PUT, POST, DELETE."
  }
}

variable "object_expiration_days" {
  description = "Delete current objects this many days after creation. Useful for transient assets (logs, temporary exports). Null keeps objects indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || try(var.object_expiration_days >= 1, false)
    error_message = "object_expiration_days must be null or at least 1."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long to keep previous versions of overwritten or deleted objects before they are permanently removed. This is your undo window for accidental deletes/overwrites."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "enable_intelligent_tiering" {
  description = "Automatically move objects to cheaper storage tiers based on access patterns. Recommended for buckets holding large or infrequently-read assets (videos, archives)."
  type        = bool
  default     = true
}

variable "access_log_bucket" {
  description = "Name of an existing S3 bucket to deliver server access logs to. Null disables access logging."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow 'tofu destroy' to delete the bucket even if it contains objects. Keep false for anything holding real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
