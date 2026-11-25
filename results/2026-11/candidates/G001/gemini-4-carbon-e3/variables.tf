variable "app_name" {
  description = "Name of the application or service that owns this bucket (lowercase letters, numbers, and hyphens, e.g., 'checkout-api')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.app_name)) && !can(regex("--", var.app_name))
    error_message = "app_name must be 1-30 characters of lowercase letters, numbers, and single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g., 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.environment)) && !can(regex("--", var.environment))
    error_message = "environment must be 1-16 characters of lowercase letters, numbers, and single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "purpose" {
  description = "Short slug describing what the bucket stores (e.g., 'assets', 'uploads', 'media', 'generated-files', 'logs'). Allows an application to cleanly own multiple buckets."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 1-20 characters of lowercase letters, numbers, and single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit S3 bucket name. Leave null to use the standard globally unique naming convention (<app_name>-<purpose>-<environment>-<account_id>-<region>)."
  type        = string
  default     = null

  validation {
    condition = (
      var.bucket_name_override == null || (
        can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name_override)) &&
        !can(regex("\\.\\.|\\.\\-|\\-\\.", var.bucket_name_override)) &&
        !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.bucket_name_override)) &&
        !startswith(var.bucket_name_override, "xn--") &&
        !startswith(var.bucket_name_override, "sthree-") &&
        !endswith(var.bucket_name_override, "-s3alias") &&
        !endswith(var.bucket_name_override, "--ol-s3")
      )
    )
    error_message = "bucket_name_override must follow AWS S3 bucket naming rules (3-63 lowercase characters, numbers, hyphens, or dots, not formatted as an IP address or reserved prefix/suffix)."
  }
}

variable "versioning_enabled" {
  description = "Whether object versioning is enabled to protect against accidental overwrites and deletions. Enabled by default."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key to encrypt bucket objects. Mutually exclusive with create_kms_key. When null and create_kms_key is false, SSE-S3 (AES256) encryption is used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN (not an alias ARN)."
  }
}

variable "create_kms_key" {
  description = "Whether to provision a dedicated customer-managed KMS key (with automatic annual rotation) for this bucket. Set to true when compliance requires customer-managed keys."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "High-level lifecycle settings controlling automatic storage cost optimization, optional object expiration (TTL), noncurrent version cleanup, and incomplete multipart upload cleanup."
  type = object({
    enable_intelligent_tiering             = optional(bool, true)
    intelligent_tiering_days               = optional(number, 30)
    expiration_days                        = optional(number, null)
    noncurrent_version_expiration_days     = optional(number, 90)
    noncurrent_versions_to_retain          = optional(number, null)
    abort_incomplete_multipart_upload_days = optional(number, 7)
  })
  default = {}

  validation {
    condition     = var.lifecycle_rules.intelligent_tiering_days >= 0 && floor(var.lifecycle_rules.intelligent_tiering_days) == var.lifecycle_rules.intelligent_tiering_days
    error_message = "lifecycle_rules.intelligent_tiering_days must be a non-negative integer."
  }

  validation {
    condition     = var.lifecycle_rules.expiration_days == null || (var.lifecycle_rules.expiration_days >= 1 && floor(var.lifecycle_rules.expiration_days) == var.lifecycle_rules.expiration_days)
    error_message = "lifecycle_rules.expiration_days must be null or an integer >= 1."
  }

  validation {
    condition     = var.lifecycle_rules.noncurrent_version_expiration_days >= 1 && floor(var.lifecycle_rules.noncurrent_version_expiration_days) == var.lifecycle_rules.noncurrent_version_expiration_days
    error_message = "lifecycle_rules.noncurrent_version_expiration_days must be an integer >= 1."
  }

  validation {
    condition     = var.lifecycle_rules.noncurrent_versions_to_retain == null || (var.lifecycle_rules.noncurrent_versions_to_retain >= 1 && var.lifecycle_rules.noncurrent_versions_to_retain <= 100 && floor(var.lifecycle_rules.noncurrent_versions_to_retain) == var.lifecycle_rules.noncurrent_versions_to_retain)
    error_message = "lifecycle_rules.noncurrent_versions_to_retain must be null or an integer between 1 and 100."
  }

  validation {
    condition     = var.lifecycle_rules.abort_incomplete_multipart_upload_days >= 1 && floor(var.lifecycle_rules.abort_incomplete_multipart_upload_days) == var.lifecycle_rules.abort_incomplete_multipart_upload_days
    error_message = "lifecycle_rules.abort_incomplete_multipart_upload_days must be an integer >= 1."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-based direct uploads (e.g., presigned URLs) or web asset delivery."
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = optional(list(string), ["GET", "HEAD"])
    allowed_headers = optional(list(string), ["*"])
    expose_headers  = optional(list(string), ["ETag"])
    max_age_seconds = optional(number, 3600)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_origins) > 0 &&
      length(rule.allowed_methods) > 0 &&
      rule.max_age_seconds >= 0 &&
      alltrue([for m in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    ])
    error_message = "Each CORS rule must specify at least one allowed_origin, non-negative max_age_seconds, and valid HTTP methods (GET, PUT, POST, DELETE, HEAD)."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs permitted to read objects from this bucket via Origin Access Control (OAC)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.cloudfront_distribution_arns :
      can(regex("^arn:aws(-[a-z]+)?:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))
    ])
    error_message = "All entries in cloudfront_distribution_arns must be valid CloudFront distribution ARNs."
  }
}

variable "read_only_principal_arns" {
  description = "Optional IAM principal ARNs (e.g., task/execution/service roles) granted read-only object access directly via the bucket policy (and KMS key policy if create_kms_key is true)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.read_only_principal_arns :
      can(regex("^arn:aws(-[a-z]+)?:iam::[0-9]{12}:(root|(role|user)/.+)$", arn))
    ])
    error_message = "All entries in read_only_principal_arns must be valid IAM principal ARNs."
  }
}

variable "read_write_principal_arns" {
  description = "Optional IAM principal ARNs (e.g., application task/pod/Lambda roles) granted read-write object access directly via the bucket policy (and KMS key policy if create_kms_key is true)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.read_write_principal_arns :
      can(regex("^arn:aws(-[a-z]+)?:iam::[0-9]{12}:(root|(role|user)/.+)$", arn))
    ])
    error_message = "All entries in read_write_principal_arns must be valid IAM principal ARNs."
  }
}

variable "create_iam_policies" {
  description = "Whether to create managed IAM policies (read-only and read-write) that application teams can attach directly to their service/task/Lambda IAM roles."
  type        = bool
  default     = true
}

variable "access_logging" {
  description = "Optional S3 server access logging configuration. Provide target_bucket (and optional target_prefix) to ship access logs to a centralized audit bucket."
  type = object({
    target_bucket = string
    target_prefix = optional(string, null)
  })
  default = null

  validation {
    condition     = var.access_logging == null || length(trimspace(var.access_logging.target_bucket)) >= 3
    error_message = "access_logging.target_bucket must be a valid non-empty S3 bucket name."
  }
}

variable "enable_eventbridge" {
  description = "Whether to emit S3 object notifications to Amazon EventBridge, enabling event-driven workflows (e.g., async media processing) without modifying bucket notification rules later."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete all objects and versions when destroying the bucket. Defaults to false to prevent accidental data loss; only enable in ephemeral/non-production environments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge with the standard module tags."
  type        = map(string)
  default     = {}
}
