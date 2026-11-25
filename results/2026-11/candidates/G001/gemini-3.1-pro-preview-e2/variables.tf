variable "bucket_name" {
  description = "The globally unique name of the S3 bucket."
  type        = string
}

variable "app_name" {
  description = "The name of the application that owns this bucket."
  type        = string
}

variable "environment" {
  description = "The environment this bucket is for (e.g., dev, staging, prod)."
  type        = string
}

variable "versioning_enabled" {
  description = "Whether to enable versioning for the bucket. Recommended for application assets to prevent accidental data loss."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Whether to allow destroying the bucket even if it contains objects. Useful for dev environments."
  type        = bool
  default     = false
}

variable "enable_default_lifecycle_rules" {
  description = "Whether to enable default lifecycle rules (abort incomplete multipart uploads, transition old versions to IA, expire old versions)."
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of origins allowed to make cross-origin requests. E.g. ['https://example.com']."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
