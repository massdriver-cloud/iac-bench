variable "name" {
  description = "Short name for the bucket, e.g. \"myapp-uploads\". The AWS account ID is appended automatically so the name is globally unique. Lowercase letters, numbers and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$", var.name))
    error_message = "name must be 3-50 characters: lowercase letters, numbers and hyphens, starting and ending with a letter or number."
  }
}

variable "versioning_enabled" {
  description = "Keep previous versions of overwritten/deleted objects so mistakes can be recovered. Old versions are expired after noncurrent_version_expiration_days."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which old (overwritten or deleted) object versions are permanently removed. Only applies when versioning is enabled."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "expiration_days" {
  description = "If set, current objects are automatically deleted this many days after creation (useful for logs and temporary generated files). Null keeps objects forever."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || try(var.expiration_days >= 1, false)
    error_message = "expiration_days must be null or at least 1."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for encryption. Null uses S3-managed encryption (SSE-S3), which needs no key management."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "Browser origins (e.g. [\"https://app.example.com\"]) allowed to upload to / download from the bucket directly. Empty disables CORS."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it contains objects. Leave false for anything holding real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
