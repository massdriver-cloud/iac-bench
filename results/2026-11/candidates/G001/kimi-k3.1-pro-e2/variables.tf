variable "application" {
  description = "Lowercase application name used in bucket names and mandatory tags (2-32 characters; letters, numbers, and internal hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])$", var.application))
    error_message = "application must be 2-32 lowercase letters, numbers, or hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Lowercase environment name used in bucket names and mandatory tags (for example, dev, staging, or prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,14}[a-z0-9])$", var.environment))
    error_message = "environment must be 2-16 lowercase letters, numbers, or hyphens, and must start and end with a letter or number."
  }
}

variable "bucket_name" {
  description = "Optional exact S3 bucket name. Leave null to let S3 generate a globally unique name from the application and environment."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name == null || (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("[.][.]", var.bucket_name)) &&
      !can(regex("^\\d{1,3}(?:\\.\\d{1,3}){3}$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid S3 bucket name: 3-63 lowercase letters, numbers, dots, or hyphens; not an IP address; and without adjacent dots."
  }
}

variable "tags" {
  description = "Additional tags. Application, Environment, and ManagedBy are always set by the module and cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete all objects and versions when destroying the buckets. Keep false outside disposable environments."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Keep prior object versions for recovery from accidental overwrite or deletion."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to retain noncurrent object versions when versioning is enabled. Current objects are never expired by the module."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && var.noncurrent_version_expiration_days <= 36500 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number between 1 and 36500."
  }
}

variable "incomplete_multipart_upload_days" {
  description = "Number of days after which incomplete multipart uploads are aborted to avoid orphaned storage charges."
  type        = number
  default     = 7

  validation {
    condition     = var.incomplete_multipart_upload_days >= 1 && var.incomplete_multipart_upload_days <= 365 && floor(var.incomplete_multipart_upload_days) == var.incomplete_multipart_upload_days
    error_message = "incomplete_multipart_upload_days must be a whole number between 1 and 365."
  }
}

variable "access_logging_enabled" {
  description = "Create a dedicated, private bucket and enable S3 server access logging. The log bucket is encrypted and its logs expire automatically."
  type        = bool
  default     = true
}

variable "access_log_retention_days" {
  description = "Number of days to retain server access logs in the dedicated log bucket."
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days >= 1 && var.access_log_retention_days <= 36500 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "access_log_retention_days must be a whole number between 1 and 36500."
  }
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing KMS key for bucket encryption. Leave null to use no-extra-cost S3-managed encryption (AES256). The key policy must permit the bucket's users and S3."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a full KMS key ARN (not an alias ARN)."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-based uploads or downloads. No cross-origin access is allowed when this is empty."
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string), [])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_methods) > 0 &&
      length(rule.allowed_origins) > 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "PUT", "HEAD", "POST", "DELETE"], method)]) &&
      (rule.max_age_seconds == null || rule.max_age_seconds >= 0)
    ])
    error_message = "Each CORS rule needs at least one origin and method; methods must be GET, PUT, HEAD, POST, or DELETE, and max_age_seconds cannot be negative."
  }
}
