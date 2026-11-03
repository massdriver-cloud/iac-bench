variable "application" {
  type        = string
  description = "Short, stable name of the application or team that owns this bucket. Used to build the generated bucket name and resource tags."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.application))
    error_message = "application must be 1-32 characters, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment for this bucket, for example dev, staging, or production. Used to build the generated bucket name and resource tags."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-16 characters, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "bucket_name" {
  type        = string
  default     = null
  description = "Optional explicit, globally unique S3 bucket name. When omitted, the module generates a unique name from application and environment."

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name, when set, must be 3-63 characters, contain only lowercase letters, numbers, and hyphens (no periods), and start and end with a letter or number."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow OpenTofu to delete the bucket even when it still contains objects. Leave false for production buckets."
}

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Enable S3 object versioning so accidental overwrites and deletions can be recovered."
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Permanently delete noncurrent object versions after this many days. Set to null to keep noncurrent versions forever. Only applied when versioning is enabled."

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days > 0
    error_message = "noncurrent_version_expiration_days must be greater than 0, or null to disable expiration."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  default     = 7
  description = "Automatically delete incomplete multipart uploads after this many days so they do not accumulate storage charges."

  validation {
    condition     = var.abort_incomplete_multipart_upload_days > 0
    error_message = "abort_incomplete_multipart_upload_days must be greater than 0."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the bucket and its configuration resources."
}
