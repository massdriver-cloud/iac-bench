variable "name" {
  description = "Name of the bucket. Must be globally unique across AWS (e.g. \"acme-checkout-prod-assets\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name)) && !can(regex("\\.\\.", var.name))
    error_message = "name must be 3-63 characters of lowercase letters, numbers, hyphens and dots, starting and ending with a letter or number."
  }
}

variable "tags" {
  description = "Tags applied to every resource (e.g. owner, team, environment, cost-center)."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Keep previous versions of overwritten/deleted objects so accidental changes can be recovered. Old versions expire after noncurrent_version_expiration_days."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which old (overwritten or deleted) object versions are permanently removed. Only used when versioning is enabled."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "expiration_days" {
  description = "Optional: automatically delete current objects this many days after creation (useful for temporary or generated files, logs). null keeps objects forever."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || coalesce(var.expiration_days, 1) >= 1
    error_message = "expiration_days must be null or at least 1."
  }
}

variable "kms_key_arn" {
  description = "Optional: ARN of a customer-managed KMS key for encryption. null uses S3-managed encryption (SSE-S3), which needs no key management."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "Browser origins (e.g. [\"https://app.example.com\"]) allowed to read/upload objects directly from the bucket. Empty disables CORS."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests. Only used when cors_allowed_origins is set."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]
}

variable "access_log_bucket" {
  description = "Optional: name of an existing bucket to receive S3 server access logs. null disables access logging."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it contains objects. Leave false for anything holding real data."
  type        = bool
  default     = false
}
