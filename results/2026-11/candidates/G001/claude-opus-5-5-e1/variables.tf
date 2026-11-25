# ---------------------------------------------------------------------------
# Required inputs — the only things an app team must decide.
# ---------------------------------------------------------------------------

variable "application" {
  description = "Short name of the application that owns this bucket (lowercase letters, digits and hyphens, 2-16 chars). Example: \"photo-api\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", var.application))
    error_message = "application must be 2-16 chars, lowercase letters/digits/hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. One of: dev, test, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — sensible, secure defaults. Most teams never touch these.
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "us-east-1"
}

variable "purpose" {
  description = "What the bucket holds, used in the bucket name so one app can have several buckets (e.g. \"uploads\", \"media\", \"exports\"). 2-10 chars."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", var.purpose))
    error_message = "purpose must be 2-10 chars, lowercase letters/digits/hyphens, start with a letter and not end with a hyphen."
  }
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to read/upload directly (e.g. via pre-signed URLs), such as [\"https://app.example.com\"]. Leave empty if only your backend talks to the bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https?://[^/*]+(:[0-9]+)?$|^https://\\*\\.[^/]+$", o))])
    error_message = "Each CORS origin must be a scheme + host (e.g. https://app.example.com) with no path. \"*\" is not allowed."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long overwritten or deleted object versions are kept (so mistakes can be undone) before being permanently removed."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 1 and 3650."
  }
}

variable "expire_objects_after_days" {
  description = "If set, current objects are automatically deleted this many days after upload (useful for temporary files, generated exports or logs). null = keep forever."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || try(var.expire_objects_after_days >= 1, false)
    error_message = "expire_objects_after_days must be null or >= 1."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for encryption. null = S3-managed encryption (SSE-S3), which is right for almost everyone."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "force_destroy" {
  description = "Allow `tofu destroy` to delete the bucket even when it contains objects. Never allowed for prod."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags to apply to all resources."
  type        = map(string)
  default     = {}
}
