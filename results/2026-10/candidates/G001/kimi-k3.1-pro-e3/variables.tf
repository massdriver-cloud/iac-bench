variable "application_name" {
  description = "Short, lowercase application identifier used in the bucket name and tags (for example, orders-web)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.application_name))
    error_message = "application_name must be 3-24 characters and contain only lowercase letters, numbers, and hyphens; it must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Lowercase deployment environment used in the bucket name and tags (for example, dev, staging, or prod)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,8}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-10 characters and contain only lowercase letters, numbers, and hyphens; it must start and end with a letter or number."
  }
}

variable "bucket_name" {
  description = "Optional explicit S3 bucket name. Leave null to generate a unique, predictable name from the application, environment, AWS account, and Region."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name == null ? true : (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.bucket_name)) &&
      !can(regex("\\.\\.", var.bucket_name)) &&
      !can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn_s3_demo_)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|\\.mrap|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid 3-63 character general-purpose S3 bucket name, not an IP address, and must not use S3-reserved prefixes or suffixes."
  }
}

variable "tags" {
  description = "Additional tags for the bucket. Application, Environment, ManagedBy, and Name are supplied by the module and cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "force_destroy" {
  description = "Whether OpenTofu may delete all objects and versions when destroying the bucket. Keep false to prevent accidental data loss."
  type        = bool
  default     = false
  nullable    = false
}

variable "versioning_enabled" {
  description = "Whether S3 object versioning is enabled. Enabled by default to protect against overwrites and deletes."
  type        = bool
  default     = true
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing customer-managed KMS key for bucket encryption. Leave null to use S3-managed encryption keys (SSE-S3)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a full KMS key ARN (not an alias ARN). Standard and multi-Region key IDs are supported."
  }
}

variable "object_expiration_days" {
  description = "Optional number of days after which current object versions expire. Leave null to retain application assets indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null ? true : var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days
    error_message = "object_expiration_days must be null or a positive whole number of days."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent object versions when versioning is enabled. Set null to retain them indefinitely; ignored when versioning is disabled."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days == null ? true : var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be null or a positive whole number of days."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads are aborted to avoid orphaned storage charges."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a positive whole number of days."
  }
}

variable "access_logging" {
  description = "Optional server access logging destination. The target bucket must already exist and permit S3 log delivery; do not use this bucket as its own destination."
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  default = null
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-based applications. No CORS access is allowed by default."
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number)
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(var.cors_rules) <= 100
    error_message = "S3 supports at most 100 CORS rules per bucket."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules : length(rule.allowed_methods) > 0 && length(rule.allowed_origins) > 0
    ])
    error_message = "Every CORS rule must specify at least one allowed method and one allowed origin."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.cors_rules : [
        for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)
      ]
    ]))
    error_message = "CORS allowed_methods may contain only GET, PUT, POST, DELETE, and HEAD (uppercase)."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules : rule.max_age_seconds == null ? true : rule.max_age_seconds >= 0 && floor(rule.max_age_seconds) == rule.max_age_seconds
    ])
    error_message = "CORS max_age_seconds must be null or a non-negative whole number."
  }
}

variable "additional_bucket_policy_json" {
  description = "Optional JSON IAM policy document with additional bucket policy statements. The module always adds its own deny-insecure-transport statement."
  type        = string
  default     = null

  validation {
    condition = var.additional_bucket_policy_json == null ? true : (
      can(jsondecode(var.additional_bucket_policy_json)) &&
      can(jsondecode(var.additional_bucket_policy_json).Statement)
    )
    error_message = "additional_bucket_policy_json must be null or a valid IAM policy JSON document containing Statement."
  }
}
