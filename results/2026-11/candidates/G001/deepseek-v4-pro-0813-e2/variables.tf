variable "name" {
  description = "Short, lowercase application or service name. Used as part of the S3 bucket name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name)) && length(var.name) <= 32
    error_message = "`name` must be 1-32 characters, contain only lowercase letters, numbers, and hyphens, and start/end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment name, for example dev, staging, or prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.environment)) && length(var.environment) <= 12
    error_message = "`environment` must be 1-12 characters, contain only lowercase letters, numbers, and hyphens, and start/end with a letter or number."
  }
}

variable "region" {
  description = "AWS region where the bucket is created."
  type        = string
  default     = "us-east-1"
}

variable "versioning_enabled" {
  description = "Keep multiple versions of objects so accidental overwrites or deletions can be recovered."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. Keep this false for any environment with real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "noncurrent_version_expiration_days" {
  description = "Delete non-current object versions after this many days. Set to 0 to keep them indefinitely."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 0
    error_message = "`noncurrent_version_expiration_days` must be greater than or equal to 0."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Abort multipart uploads that are not completed after this many days. Set to 0 to disable this rule."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 0
    error_message = "`abort_incomplete_multipart_upload_days` must be greater than or equal to 0."
  }
}
