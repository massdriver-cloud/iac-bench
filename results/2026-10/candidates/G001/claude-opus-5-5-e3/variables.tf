# ---------------------------------------------------------------------------
# Required inputs — the only things most teams need to fill in.
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Short name of the application that owns this bucket (lowercase letters, digits, hyphens). Used in the bucket name and tags, e.g. \"photo-share\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-24 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. \"dev\", \"staging\", \"prod\". Used in the bucket name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,8}[a-z0-9]$", var.environment)) || can(regex("^[a-z0-9]$", var.environment))
    error_message = "environment must be 1-10 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — safe defaults; change only if you have a reason.
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Extra tags to apply to all resources (e.g. team, cost-center)."
  type        = map(string)
  default     = {}
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to access the bucket directly (e.g. for uploads via pre-signed URLs), such as [\"https://app.example.com\"]. Leave empty if browsers never talk to the bucket directly."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https?://", o)) && o != "*"])
    error_message = "Each CORS origin must be a full origin starting with https:// (or http:// for local development). Wildcard \"*\" is not allowed."
  }
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key for encryption. When null (default), objects are encrypted with S3-managed keys (SSE-S3), which needs no key management."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How many days overwritten or deleted object versions are kept (so they can be recovered) before being permanently removed."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number >= 1."
  }
}

variable "expire_objects_after_days" {
  description = "Optional: automatically delete objects this many days after creation (useful for logs or temporary generated files). Null (default) keeps objects forever."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || try(var.expire_objects_after_days >= 1 && floor(var.expire_objects_after_days) == var.expire_objects_after_days, false)
    error_message = "expire_objects_after_days must be null or a whole number >= 1."
  }
}

variable "intelligent_tiering_enabled" {
  description = "Move objects to the S3 Intelligent-Tiering storage class after 30 days so rarely-accessed assets automatically get cheaper storage, with no retrieval fees or performance change."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. Keep false for anything holding real data; only set true for throwaway environments."
  type        = bool
  default     = false
}
