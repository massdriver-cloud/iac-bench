# -----------------------------------------------------------------------------
# Required Inputs (the only inputs an app team must provide)
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the application that owns this bucket (lowercase letters, numbers, and hyphens, e.g. \"checkout-service\")."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.app_name)) && !can(regex("--", var.app_name))
    error_message = "app_name must be 2-40 characters, contain only lowercase letters, numbers, and single hyphens, and start and end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment name (lowercase letters, numbers, and hyphens, e.g. \"dev\", \"staging\", \"prod\")."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,14}[a-z0-9]$", var.environment)) && !can(regex("--", var.environment))
    error_message = "environment must be 2-16 characters, contain only lowercase letters, numbers, and single hyphens, and start and end with a letter or number."
  }
}

# -----------------------------------------------------------------------------
# Naming & Identity
# -----------------------------------------------------------------------------

variable "purpose" {
  description = "Short label for what this bucket stores (e.g. \"assets\", \"uploads\", \"media\", \"generated-files\", \"logs\"). Set this when an application needs more than one bucket in the same environment."
  type        = string
  default     = "assets"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,22}[a-z0-9]$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 2-24 characters, contain only lowercase letters, numbers, and single hyphens, and start and end with a letter or number."
  }
}

variable "bucket_name_override" {
  description = "Explicit S3 bucket name override. Leave null to use the standard globally unique naming convention (<app_name>-<purpose>-<environment>-<account_id>-<region>)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.bucket_name_override == null || (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name_override)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name_override)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3)$", var.bucket_name_override)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket_name_override))
    )
    error_message = "bucket_name_override must be 3-63 characters of lowercase letters, numbers, and hyphens, and satisfy AWS S3 bucket naming rules."
  }
}

variable "tags" {
  description = "Additional tags to apply to the bucket and related resources. Merged with automatic Application, Environment, Purpose, and ManagedBy tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

# -----------------------------------------------------------------------------
# Data Protection, Versioning & Lifecycle
# -----------------------------------------------------------------------------

variable "versioning_enabled" {
  description = "Keep historical versions of overwritten or deleted objects so accidental changes can be recovered."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_intelligent_tiering" {
  description = "Automatically transition objects (>= 128 KB) into S3 Intelligent-Tiering to reduce storage costs on infrequently accessed files with zero retrieval fees or latency impact."
  type        = bool
  default     = true
  nullable    = false
}

variable "intelligent_tiering_days" {
  description = "Number of days after creation before objects (>= 128 KB) transition to S3 Intelligent-Tiering (0 enrolls objects immediately)."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.intelligent_tiering_days >= 0 && floor(var.intelligent_tiering_days) == var.intelligent_tiering_days
    error_message = "intelligent_tiering_days must be a non-negative integer."
  }
}

variable "object_expiration_days" {
  description = "Automatically expire (delete) all objects after this many days. Leave null to keep objects indefinitely (recommended for user uploads and media); set e.g. 30 or 90 for temporary generated files or logs."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be null or a positive integer >= 1."
  }
}

variable "prefix_expiration_rules" {
  description = "Optional map of key prefixes to expiration days for buckets with mixed retention needs (e.g. { \"tmp/\" = 7, \"exports/\" = 30 })."
  type        = map(number)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for prefix, days in var.prefix_expiration_rules :
      length(trimspace(prefix)) > 0 && days >= 1 && floor(days) == days
    ])
    error_message = "Each entry in prefix_expiration_rules must have a non-empty prefix key and an integer expiration >= 1 day."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain overwritten or deleted object versions before permanently removing them."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a positive integer >= 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days before incomplete/abandoned multipart uploads are automatically aborted and their parts cleaned up."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a positive integer >= 1."
  }
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete the bucket even if it still contains objects and versions. Keep false in production; set true only for ephemeral/dev environments."
  type        = bool
  default     = false
  nullable    = false
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "create_kms_key" {
  description = "Create a dedicated, automatically rotated AWS KMS customer-managed key for server-side encryption. When false and kms_key_arn is null, S3-managed encryption (SSE-S3 / AES256) is used."
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_arn" {
  description = "ARN of an existing AWS KMS key to use for server-side encryption (SSE-KMS). Leave null to use SSE-S3 (or set create_kms_key = true to create a dedicated key)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a valid AWS KMS key ARN."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period (7-30 days) before a module-created KMS key is permanently deleted after destruction."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be an integer between 7 and 30."
  }
}

# -----------------------------------------------------------------------------
# Browser Uploads / Downloads (CORS) & CDN Delivery (CloudFront OAC)
# -----------------------------------------------------------------------------

variable "cors_allowed_origins" {
  description = "List of origins (e.g. [\"https://app.example.com\"]) allowed to make cross-origin browser requests (such as presigned URL uploads/downloads). Leave empty to disable CORS."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for origin in var.cors_allowed_origins : length(trimspace(origin)) > 0 && origin != "*"])
    error_message = "cors_allowed_origins entries must be explicit origin URLs (wildcard \"*\" is not permitted; specify exact origins such as \"https://app.example.com\")."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]
  nullable    = false

  validation {
    condition = length(var.cors_allowed_methods) > 0 && alltrue([
      for method in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)
    ])
    error_message = "cors_allowed_methods must be a non-empty subset of [\"GET\", \"HEAD\", \"PUT\", \"POST\", \"DELETE\"]."
  }
}

variable "cors_allowed_headers" {
  description = "Request headers allowed in CORS preflight requests."
  type        = list(string)
  default     = ["*"]
  nullable    = false
}

variable "cors_expose_headers" {
  description = "Response headers exposed to browsers on CORS requests (ETag is required by browser multipart upload clients)."
  type        = list(string)
  default     = ["ETag", "x-amz-request-id", "x-amz-version-id"]
  nullable    = false
}

variable "cors_max_age_seconds" {
  description = "How long (in seconds) browsers can cache CORS preflight responses."
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "cors_max_age_seconds must be between 0 and 86400 seconds."
  }
}

variable "cloudfront_distribution_arns" {
  description = "ARNs of CloudFront distributions permitted to read objects from this bucket via Origin Access Control (OAC)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.cloudfront_distribution_arns :
      can(regex("^arn:aws(-[a-z]+)?:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))
    ])
    error_message = "Each entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

# -----------------------------------------------------------------------------
# Application IAM Access, Event Notifications & Access Logging
# -----------------------------------------------------------------------------

variable "create_iam_policies" {
  description = "Create ready-to-attach managed IAM policies (<bucket>-read-only and <bucket>-read-write) scoped to this bucket and its encryption key."
  type        = bool
  default     = true
  nullable    = false
}

variable "read_write_iam_role_names" {
  description = "IAM role names (e.g. ECS task role, EKS IRSA/Pod Identity role, Lambda execution role) to automatically grant read/write access to this bucket."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "read_only_iam_role_names" {
  description = "IAM role names to automatically grant read-only access to this bucket."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "enable_eventbridge" {
  description = "Publish S3 object events (created, deleted, restored, tagged) to Amazon EventBridge for asynchronous background processing."
  type        = bool
  default     = false
  nullable    = false
}

variable "logging_target_bucket" {
  description = "Name of a centralized S3 access-logging bucket. Leave null if S3 server access logs are not used or CloudTrail Data Events handle auditing."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.logging_target_bucket == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.logging_target_bucket))
    error_message = "logging_target_bucket must be null or a valid S3 bucket name."
  }
}

variable "logging_target_prefix" {
  description = "Optional key prefix in logging_target_bucket for access logs. Defaults to \"s3-access-logs/<bucket_name>/\" when logging_target_bucket is set."
  type        = string
  default     = null
  nullable    = true
}
