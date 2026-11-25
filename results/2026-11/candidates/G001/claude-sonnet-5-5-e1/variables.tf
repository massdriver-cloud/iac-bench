variable "name" {
  description = "Globally unique bucket name (3-63 chars, lowercase letters, digits, hyphens). Example: \"acme-photos-prod\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters: lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Tags applied to the bucket (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Keep previous versions of overwritten/deleted objects so mistakes can be recovered. Recommended on; turn off for easily regenerated data such as logs or caches."
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old object versions before permanently deleting them (only meaningful with versioning)."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "expire_objects_after_days" {
  description = "Automatically delete objects this many days after creation. null (default) keeps objects forever. Useful for logs and temporary generated files."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || var.expire_objects_after_days >= 1
    error_message = "expire_objects_after_days must be null or at least 1."
  }
}

variable "infrequent_access_after_days" {
  description = "Move objects to the cheaper Standard-IA storage class after this many days. null (default) disables. Must be >= 30, and less than expire_objects_after_days if both are set."
  type        = number
  default     = null

  validation {
    condition     = var.infrequent_access_after_days == null || var.infrequent_access_after_days >= 30
    error_message = "infrequent_access_after_days must be null or at least 30 (an S3 requirement)."
  }
}

variable "kms_key_arn" {
  description = "ARN of a KMS key for encryption. null (default) uses S3-managed keys (SSE-S3). Objects are always encrypted either way."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "Browser origins (e.g. [\"https://app.example.com\"]) allowed to read/upload directly to the bucket. Empty (default) disables CORS."
  type        = list(string)
  default     = []
}

variable "access_log_bucket" {
  description = "Name of an existing bucket to receive S3 server access logs. null (default) disables access logging."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow `tofu destroy` to delete the bucket even when it contains objects. Default false protects data."
  type        = bool
  default     = false
}
