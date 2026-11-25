variable "application_name" {
  description = "Short lowercase name of the application that owns the bucket (e.g. \"billing-portal\"). Used in the bucket name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.application_name))
    error_message = "application_name must be 3-30 characters, start with a letter, contain only lowercase letters, digits and hyphens, and must not end with a hyphen."
  }

  validation {
    condition     = !can(regex("--", var.application_name))
    error_message = "application_name must not contain consecutive hyphens."
  }
}

variable "environment" {
  description = "Deployment environment the bucket belongs to."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "asset_class" {
  description = <<-EOT
    What kind of assets the bucket holds. Drives the module's defaults:
      uploads   - user-provided files. Browser uploads/downloads allowed via allowed_origins.
      media     - images and videos. Browser downloads allowed via allowed_origins.
      generated - files the application produces and can regenerate. Current objects expire after 90 days by default.
      logs      - application logs. Current objects expire after 365 days by default. No browser access.
  EOT
  type        = string
  default     = "uploads"

  validation {
    condition     = contains(["uploads", "media", "generated", "logs"], var.asset_class)
    error_message = "asset_class must be one of: uploads, media, generated, logs."
  }
}

variable "owning_team" {
  description = "Team responsible for the bucket (tagged on the bucket, used for cost and ownership reporting)."
  type        = string

  validation {
    condition     = length(trimspace(var.owning_team)) > 0 && length(var.owning_team) <= 64
    error_message = "owning_team must be a non-empty string of at most 64 characters."
  }
}

variable "allowed_origins" {
  description = "Browser origins allowed to access the bucket via CORS (e.g. [\"https://app.example.com\"]). Only valid for uploads and media. Empty list disables CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.allowed_origins : can(regex("^https://[^*\\s]+$", o)) || can(regex("^http://localhost(:[0-9]+)?$", o))])
    error_message = "Each allowed origin must be an https:// origin (no wildcards), or http://localhost with an optional port."
  }
}

variable "retention_days" {
  description = "Days after which current objects expire. null (default) uses the asset_class default: generated 90, logs 365; uploads and media never expire. Set a number to override."
  type        = number
  default     = null

  validation {
    condition     = var.retention_days == null ? true : (var.retention_days >= 1 && var.retention_days <= 36500)
    error_message = "retention_days must be null or between 1 and 36500."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for default encryption. null uses SSE-S3 (AES256)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a valid KMS key ARN."
  }
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. Keep false outside of throwaway environments."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "us-east-1"
}

variable "additional_tags" {
  description = "Extra tags to apply to the bucket. Module tags take precedence on key collisions."
  type        = map(string)
  default     = {}
}
