################################################################################
# Required Inputs
################################################################################

variable "app_name" {
  description = "Short, lowercase name of the application or service that owns this bucket (e.g. 'checkout', 'media-api'). Used in bucket naming and standard tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.app_name)) && length(var.app_name) >= 2
    error_message = "app_name must be 2 to 24 characters long, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment for the bucket (e.g. 'dev', 'staging', 'prod'). Production environments block force_destroy by default."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$", var.environment)) && length(var.environment) >= 2
    error_message = "environment must be 2 to 12 characters long, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

################################################################################
# Naming & Tagging
################################################################################

variable "purpose" {
  description = "Short label describing what this bucket stores (e.g. 'assets', 'uploads', 'media', 'exports', 'logs'). Lets an app own multiple distinct buckets without naming collisions."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.purpose)) && length(var.purpose) >= 2
    error_message = "purpose must be 2 to 16 characters long, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit S3 bucket name. Leave null (recommended) to automatically generate a globally unique name of the form '<app_name>-<purpose>-<environment>-<account_id>-<region>'."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name_override == null || (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name_override)) &&
      !startswith(var.bucket_name_override, "xn--") &&
      !startswith(var.bucket_name_override, "sthree-") &&
      !endswith(var.bucket_name_override, "-s3alias") &&
      !endswith(var.bucket_name_override, "--ol-s3")
    )
    error_message = "bucket_name_override must be 3 to 63 characters, lowercase alphanumeric and hyphens only, start and end with alphanumeric, and not use reserved AWS prefixes/suffixes."
  }
}

variable "owner" {
  description = "Owning team, squad, or email address tagged on all created resources for cost attribution and incident response."
  type        = string
  default     = null
}

variable "data_classification" {
  description = "Sensitivity classification of data stored in the bucket. Applied as a tag for governance and compliance."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: 'public', 'internal', 'confidential', 'restricted'."
  }
}

variable "tags" {
  description = "Additional tags to apply to all taggable resources created by this module."
  type        = map(string)
  default     = {}
}

################################################################################
# Workload Profile & Lifecycle Management
################################################################################

variable "workload_profile" {
  description = <<-EOT
    Pre-tuned storage and lifecycle profile for common application patterns:
      - 'assets' (default): User uploads, images, videos, and general app files. Versioning on, Intelligent-Tiering for objects >= 128 KB, noncurrent versions expire after 90 days.
      - 'temporary': Generated files, exports, and scratch artifacts. Versioning off, objects expire after 30 days, incomplete uploads aborted after 3 days.
      - 'logs': Application logs and audit exports. Versioning off, automatic tiering (IA -> Glacier IR -> Glacier Flexible), objects expire after 365 days.
      - 'archive': Long-term media/compliance retention. Versioning on, automatic tiering to Glacier Instant Retrieval and Deep Archive.
    Individual lifecycle settings below can override any profile default.
  EOT
  type        = string
  default     = "assets"

  validation {
    condition     = contains(["assets", "temporary", "logs", "archive"], var.workload_profile)
    error_message = "workload_profile must be one of: 'assets', 'temporary', 'logs', 'archive'."
  }
}

variable "versioning_enabled" {
  description = "Override whether S3 object versioning is enabled. Leave null to use the workload_profile default (enabled for 'assets' and 'archive', suspended for 'temporary' and 'logs')."
  type        = bool
  default     = null
}

variable "object_expiration_days" {
  description = "Override how many days current objects are retained before automatic deletion. Leave null to use the workload_profile default (none for 'assets'/'archive', 30 for 'temporary', 365 for 'logs')."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be a whole number >= 1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Override how many days superseded (noncurrent) object versions are kept when versioning is enabled. Leave null to use the workload_profile default."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null || (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a whole number >= 1."
  }
}

variable "noncurrent_versions_to_retain" {
  description = "Minimum number of recent noncurrent versions to keep even past noncurrent_version_expiration_days (0 to expire all noncurrent versions strictly by age)."
  type        = number
  default     = 3

  validation {
    condition     = var.noncurrent_versions_to_retain >= 0 && var.noncurrent_versions_to_retain <= 100 && floor(var.noncurrent_versions_to_retain) == var.noncurrent_versions_to_retain
    error_message = "noncurrent_versions_to_retain must be a whole number between 0 and 100."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Override how many days after initiation incomplete multipart uploads are aborted to prevent hidden storage costs. Leave null to use the workload_profile default."
  type        = number
  default     = null

  validation {
    condition     = var.abort_incomplete_multipart_upload_days == null || (var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days)
    error_message = "abort_incomplete_multipart_upload_days must be a whole number >= 1."
  }
}

variable "custom_lifecycle_rules" {
  description = "Optional prefix-scoped lifecycle rules appended to the bucket's standard rules (e.g. expire 'tmp/' objects after 1 day)."
  type = list(object({
    id                                 = string
    prefix                             = string
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.custom_lifecycle_rules :
      length(r.id) > 0 &&
      (r.expiration_days != null || r.noncurrent_version_expiration_days != null || length(r.transitions) > 0) &&
      alltrue([
        for t in r.transitions :
        contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class) &&
        t.days >= 0
      ])
    ])
    error_message = "Each custom lifecycle rule must have a non-empty id, at least one action (expiration or transition), and valid S3 storage classes."
  }
}

################################################################################
# Encryption
################################################################################

variable "encryption_type" {
  description = "Server-side encryption mode: 'kms' (default, creates a dedicated auto-rotating KMS CMK with S3 Bucket Keys enabled) or 'sse_s3' (AWS-managed AES-256)."
  type        = string
  default     = "kms"

  validation {
    condition     = contains(["kms", "sse_s3"], var.encryption_type)
    error_message = "encryption_type must be either 'kms' or 'sse_s3'."
  }
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing customer-managed KMS key to use when encryption_type = 'kms'. When null, the module creates and manages a dedicated KMS key for this bucket."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN (not an alias ARN)."
  }
}

variable "kms_key_deletion_window_days" {
  description = "Waiting period in days before a module-managed KMS key is permanently deleted after destruction (7 to 30 days)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_days >= 7 && var.kms_key_deletion_window_days <= 30 && floor(var.kms_key_deletion_window_days) == var.kms_key_deletion_window_days
    error_message = "kms_key_deletion_window_days must be a whole number between 7 and 30."
  }
}

################################################################################
# Access Control & Integrations
################################################################################

variable "create_iam_policies" {
  description = "When true (default), creates ready-to-attach least-privilege read-only and read-write IAM managed policies (including required KMS permissions) for application roles."
  type        = bool
  default     = true
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs permitted to read objects from this private bucket via Origin Access Control (OAC). Automatically updates both the bucket policy and managed KMS key policy."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.cloudfront_distribution_arns :
      can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))
    ])
    error_message = "Every entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

variable "allowed_read_only_principal_arns" {
  description = "Optional IAM role or user ARNs granted read-only access via the bucket policy (and managed KMS key policy). Primarily useful for cross-account access; for same-account apps, attach the generated read_only_iam_policy_arn."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.allowed_read_only_principal_arns :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user|root)/.+$", arn)) || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:root$", arn))
    ])
    error_message = "Every entry in allowed_read_only_principal_arns must be a valid AWS IAM principal ARN."
  }
}

variable "allowed_read_write_principal_arns" {
  description = "Optional IAM role or user ARNs granted read-write access via the bucket policy (and managed KMS key policy). Primarily useful for cross-account access; for same-account apps, attach the generated read_write_iam_policy_arn."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.allowed_read_write_principal_arns :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user|root)/.+$", arn)) || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:root$", arn))
    ])
    error_message = "Every entry in allowed_read_write_principal_arns must be a valid AWS IAM principal ARN."
  }
}

variable "additional_bucket_policy_json" {
  description = "Optional JSON IAM policy document merged with the bucket's security baseline policy. Baseline TLS and encryption deny guardrails always remain enforced."
  type        = string
  default     = null
}

################################################################################
# Browser Access (CORS)
################################################################################

variable "cors_allowed_origins" {
  description = "List of browser origins (e.g. ['https://app.example.com']) allowed to access the bucket directly (for presigned uploads or direct asset fetches). Leave empty to disable CORS."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for origin in var.cors_allowed_origins :
      origin == "*" || can(regex("^https?://[^/\\s]+$", origin))
    ])
    error_message = "Each origin in cors_allowed_origins must be '*' or a valid scheme + host (e.g. 'https://app.example.com') without a trailing slash."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods permitted by the CORS rule when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must be a non-empty subset of: GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cors_allowed_headers" {
  description = "Request headers permitted by the CORS rule (defaults to ['*'] to support presigned upload headers)."
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "Response headers exposed to browser JavaScript (includes ETag by default, which is required for browser multipart uploads)."
  type        = list(string)
  default     = ["ETag", "x-amz-version-id"]
}

variable "cors_max_age_seconds" {
  description = "How long browsers cache CORS preflight responses, in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "cors_max_age_seconds must be between 0 and 86400 seconds."
  }
}

################################################################################
# Observability & Performance
################################################################################

variable "access_log_bucket_name" {
  description = "Optional name of an existing centralized S3 server access logging bucket. When provided, date-partitioned S3 access logs are delivered to it."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Optional key prefix for S3 server access logs when access_log_bucket_name is set. Defaults to 's3-access-logs/<bucket_name>/'."
  type        = string
  default     = null
}

variable "enable_eventbridge" {
  description = "When true, emits S3 object events (uploads, deletions, etc.) to the default Amazon EventBridge event bus for event-driven processing (e.g. thumbnail generation, virus scanning)."
  type        = bool
  default     = false
}

variable "enable_transfer_acceleration" {
  description = "When true, enables S3 Transfer Acceleration for faster global uploads of large media files (incurs additional data transfer charges)."
  type        = bool
  default     = false
}

variable "enable_request_metrics" {
  description = "When true, enables CloudWatch S3 request metrics for the entire bucket (incurs CloudWatch metrics charges)."
  type        = bool
  default     = false
}

################################################################################
# Lifecycle Safety
################################################################################

variable "force_destroy" {
  description = "Allow OpenTofu to destroy the bucket even when it still contains objects. Blocked automatically for 'prod' and 'production' environments."
  type        = bool
  default     = false
}
