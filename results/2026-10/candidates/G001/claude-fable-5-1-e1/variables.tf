###############################################################################
# Required
###############################################################################

variable "name" {
  description = <<-EOT
    Globally unique name of the bucket, e.g. "acme-photos-prod". Lowercase
    letters, digits, dots and hyphens only; 3-63 characters. A good pattern is
    "<org>-<application>-<purpose>-<environment>".
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Bucket name must be 3-63 characters of lowercase letters, digits, dots or hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = !can(regex("\\.\\.|^\\d+\\.\\d+\\.\\d+\\.\\d+$|^xn--|-s3alias$|--ol-s3$", var.name))
    error_message = "Bucket name must not contain '..', look like an IP address, start with 'xn--', or end with '-s3alias' / '--ol-s3'."
  }
}

###############################################################################
# Commonly used options
###############################################################################

variable "tags" {
  description = "Additional tags applied to the bucket (e.g. Application, Team, Environment)."
  type        = map(string)
  default     = {}
}

variable "cors_allowed_origins" {
  description = <<-EOT
    Origins allowed to access the bucket directly from a browser, e.g.
    ["https://app.example.com"]. Leave empty (the default) if your application
    only talks to the bucket from the server side. Needed for pre-signed-URL
    uploads/downloads from a web page.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cors_allowed_origins, "*")
    error_message = "Wildcard origin \"*\" is not allowed; list the exact origins your front-end is served from."
  }
}

variable "expiration_days" {
  description = <<-EOT
    Automatically delete objects this many days after they were created.
    Leave null (the default) to keep objects until your application deletes
    them. Useful for logs, temporary files and generated exports.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null ? true : var.expiration_days >= 1
    error_message = "expiration_days must be null or at least 1."
  }
}

###############################################################################
# Advanced options - the defaults are right for almost everyone
###############################################################################

variable "kms_key_arn" {
  description = <<-EOT
    ARN of a customer-managed KMS key to encrypt objects with (SSE-KMS). When
    null (the default) objects are encrypted with S3-managed keys (SSE-S3),
    which costs nothing and needs no extra IAM permissions.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "versioning_enabled" {
  description = <<-EOT
    Keep previous versions of overwritten or deleted objects so accidental
    changes can be recovered. Old versions are cleaned up automatically after
    noncurrent_version_retention_days.
  EOT
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "How long to keep previous versions of objects before they are permanently deleted. Only applies when versioning is enabled."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "intelligent_tiering_after_days" {
  description = <<-EOT
    Move objects to the S3 Intelligent-Tiering storage class this many days
    after creation so rarely accessed assets automatically become cheaper to
    store, with no change in how they are read. Set to null to keep everything
    in S3 Standard.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.intelligent_tiering_after_days == null ? true : var.intelligent_tiering_after_days >= 0
    error_message = "intelligent_tiering_after_days must be null or a non-negative number."
  }
}

variable "access_log_bucket" {
  description = "Name of an existing bucket to deliver S3 server access logs to. Leave null to disable access logging."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Key prefix for access logs in access_log_bucket. Defaults to \"<name>/\"."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = <<-EOT
    Allow `tofu destroy` to delete the bucket even when it still contains
    objects. Keep false (the default) for anything holding real data; set
    true only for throwaway/dev buckets.
  EOT
  type        = bool
  default     = false
}
