# ---------------------------------------------------------------------------
# Required inputs — the only things an app team must decide.
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Short name of the application that owns this bucket, e.g. \"photo-service\". Lowercase letters, numbers and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-24 characters of lowercase letters, numbers and hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. \"dev\", \"staging\" or \"prod\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or numbers (e.g. dev, staging, prod)."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — sensible defaults; most teams never touch these.
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region to create the bucket in. Leave null to use the region from the environment (AWS_REGION)."
  type        = string
  default     = null
}

variable "purpose" {
  description = "Optional short word describing what the bucket holds (e.g. \"uploads\", \"media\", \"logs\"). Becomes part of the bucket name; useful when an app needs more than one bucket."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.purpose))
    error_message = "purpose must be 2-10 lowercase letters or numbers."
  }
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key for encryption. Leave null to use S3-managed encryption (SSE-S3), which is right for most apps."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to read/upload directly (e.g. via presigned URLs), such as [\"https://app.example.com\"]. Leave empty if browsers never talk to the bucket directly."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : o != "*" && can(regex("^https?://", o))])
    error_message = "Each CORS origin must be an explicit http(s):// origin; \"*\" is not allowed."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long overwritten or deleted object versions are kept (for recovery from mistakes) before being permanently removed."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 1 and 3650."
  }
}

variable "expire_objects_after_days" {
  description = "Optional: automatically delete objects this many days after creation (useful for logs or temporary generated files). Leave null to keep objects forever."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || try(var.expire_objects_after_days >= 1, false)
    error_message = "expire_objects_after_days must be null or at least 1."
  }
}

variable "access_log_bucket" {
  description = "Optional name of an existing bucket to receive S3 server access logs. Leave null to disable access logging."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. Keep false outside of throwaway environments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags to apply to all resources."
  type        = map(string)
  default     = {}
}
