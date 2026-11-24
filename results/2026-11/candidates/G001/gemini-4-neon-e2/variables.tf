# ------------------------------------------------------------------------------
# Required Inputs — The only values an app team must provide
# ------------------------------------------------------------------------------

variable "app_name" {
  description = "Short, lowercase name of the application owning this bucket (e.g., 'checkout', 'media-api')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,22}[a-z0-9])?$", var.app_name)) && !can(regex("--", var.app_name))
    error_message = "app_name must be 1–24 lowercase alphanumeric characters or single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment for the application."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "staging", "prod", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, qa, staging, prod, sandbox."
  }
}

variable "owner" {
  description = "Team or owner responsible for this bucket (used for tagging, incident escalation, and cost attribution)."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) >= 2 && length(var.owner) <= 128
    error_message = "owner must be a non-empty string between 2 and 128 characters."
  }
}

# ------------------------------------------------------------------------------
# Naming & Identity (Optional)
# ------------------------------------------------------------------------------

variable "purpose" {
  description = "Short descriptor for what this bucket stores (e.g., 'assets', 'uploads', 'media', 'exports', 'logs'). Used in the generated bucket name and tags."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,18}[a-z0-9])?$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 1–20 lowercase alphanumeric characters or single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit S3 bucket name. Leave null to let the module generate a deterministic, globally unique name."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name_override == null ? true : (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name_override)) &&
      !can(regex("--", var.bucket_name_override)) &&
      !startswith(var.bucket_name_override, "xn--") &&
      !startswith(var.bucket_name_override, "sthree-") &&
      !endswith(var.bucket_name_override, "-s3alias") &&
      !endswith(var.bucket_name_override, "--ol-s3")
    )
    error_message = "bucket_name_override must be a valid DNS-compliant S3 bucket name (3–63 lowercase alphanumeric characters or single hyphens, no reserved prefixes/suffixes)."
  }
}

# ------------------------------------------------------------------------------
# Workload Profile & Lifecycle Management
# ------------------------------------------------------------------------------

variable "use_case" {
  description = <<-EOT
    Workload profile that sets sensible defaults for versioning, storage tiering, and retention:
      - "assets":    General app assets, user uploads, generated files (versioned, Intelligent-Tiering >=128KB, 90d noncurrent retention).
      - "media":     Images, videos, large rich media (versioned, Intelligent-Tiering >=128KB, 30d noncurrent retention).
      - "logs":      Application/audit logs (unversioned, transitions to IA at 30d & Glacier IR at 90d, expires at 365d).
      - "ephemeral": Temporary files & regenerable artifacts (unversioned, expires at 30d).
  EOT
  type        = string
  default     = "assets"

  validation {
    condition     = contains(["assets", "media", "logs", "ephemeral"], var.use_case)
    error_message = "use_case must be one of: assets, media, logs, ephemeral."
  }
}

variable "versioning_enabled" {
  description = "Override the use_case default for S3 object versioning. Leave null to use the profile default."
  type        = bool
  default     = null
}

variable "intelligent_tiering_enabled" {
  description = "Override the use_case default for automatically transitioning objects >= 128 KB to S3 Intelligent-Tiering. Leave null to use the profile default."
  type        = bool
  default     = null
}

variable "object_expiration_days" {
  description = "Days after creation before current object versions expire. Leave null to use the use_case default; set to 0 to explicitly disable expiration."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null ? true : (var.object_expiration_days >= 0 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be a whole number >= 0."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days after becoming noncurrent before old object versions are permanently deleted. Leave null to use the use_case default."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null ? true : (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a whole number >= 1."
  }
}

variable "noncurrent_version_transition_ia_days" {
  description = "Days after becoming noncurrent before old object versions move to STANDARD_IA. Leave null to use the use_case default; set to 0 to disable."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_transition_ia_days == null ? true : (var.noncurrent_version_transition_ia_days >= 0 && floor(var.noncurrent_version_transition_ia_days) == var.noncurrent_version_transition_ia_days)
    error_message = "noncurrent_version_transition_ia_days must be a whole number >= 0."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after initiation before incomplete multipart uploads are automatically aborted and cleaned up."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number between 1 and 365."
  }
}

variable "custom_lifecycle_rules" {
  description = "Optional additional prefix-scoped lifecycle rules for teams storing mixed workloads (e.g., expiring 'tmp/' after 7 days)."
  type = list(object({
    id                         = string
    prefix                     = string
    expiration_days            = optional(number)
    noncurrent_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.custom_lifecycle_rules :
      length(trimspace(r.id)) > 0 && (
        r.expiration_days != null || r.noncurrent_expiration_days != null || length(r.transitions) > 0
      )
    ])
    error_message = "Each custom lifecycle rule must have a non-empty id and at least one expiration or transition action."
  }
}

# ------------------------------------------------------------------------------
# Encryption & Security
# ------------------------------------------------------------------------------

variable "encryption_mode" {
  description = "Server-side encryption mode: 'kms' (SSE-KMS with S3 Bucket Key, recommended) or 'aes256' (SSE-S3)."
  type        = string
  default     = "kms"

  validation {
    condition     = contains(["kms", "aes256"], var.encryption_mode)
    error_message = "encryption_mode must be either 'kms' or 'aes256'."
  }
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing customer-managed KMS key to use when encryption_mode = 'kms'. Leave null to let the module create and manage a dedicated key with automatic rotation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period (7–30 days) before a module-managed KMS key is destroyed. Defaults to 30 in prod and 7 in non-prod."
  type        = number
  default     = null

  validation {
    condition     = var.kms_deletion_window_in_days == null ? true : (var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days)
    error_message = "kms_deletion_window_in_days must be a whole number between 7 and 30."
  }
}

variable "allow_force_destroy" {
  description = "Allow OpenTofu to destroy the bucket even if it contains objects. Always blocked when environment = 'prod'."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Access Control & Sharing
# ------------------------------------------------------------------------------

variable "create_iam_policies" {
  description = "Create ready-to-attach least-privilege IAM managed policies (read-only and read-write) scoped to this bucket and its KMS key."
  type        = bool
  default     = true
}

variable "read_principal_arns" {
  description = "Optional list of IAM principal ARNs granted read-only access via the bucket policy (useful for cross-account consumers)."
  type        = list(string)
  default     = []
}

variable "write_principal_arns" {
  description = "Optional list of IAM principal ARNs granted read-write access via the bucket policy."
  type        = list(string)
  default     = []
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs authorized to read objects via Origin Access Control (OAC). Automatically updates both the bucket policy and KMS key policy."
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

variable "additional_bucket_policy_json" {
  description = "Optional additional IAM policy JSON document merged into the bucket policy. Security guardrails (HTTPS, TLS >= 1.2, encryption header checks) are always enforced."
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Browser Uploads (CORS) & Event Notifications
# ------------------------------------------------------------------------------

variable "cors_allowed_origins" {
  description = "Optional list of browser origins allowed to access this bucket directly (e.g., ['https://app.example.com'] for presigned uploads). Leave empty to disable CORS."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "HTTP methods permitted by CORS when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must be a non-empty list containing only GET, HEAD, PUT, POST, or DELETE."
  }
}

variable "cors_allowed_headers" {
  description = "Request headers allowed in CORS preflight checks."
  type        = list(string)
  default     = ["Authorization", "Content-Type", "Content-MD5", "x-amz-*"]
}

variable "cors_expose_headers" {
  description = "Response headers exposed to browser clients (ETag is required for multipart upload completion)."
  type        = list(string)
  default     = ["ETag", "x-amz-version-id"]
}

variable "cors_max_age_seconds" {
  description = "Time in seconds browsers may cache CORS preflight responses."
  type        = number
  default     = 3600

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "cors_max_age_seconds must be between 0 and 86400."
  }
}

variable "enable_eventbridge" {
  description = "Send S3 object events to Amazon EventBridge so downstream services (thumbnails, scanning, indexing) can subscribe without colliding on bucket notification configs."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Logging & Observability
# ------------------------------------------------------------------------------

variable "enable_access_logging" {
  description = "Enable S3 server access logging. Delivers logs to access_logging_target_bucket if provided, or creates a hardened companion log bucket automatically."
  type        = bool
  default     = true
}

variable "access_logging_target_bucket" {
  description = "Optional existing centralized S3 bucket name to receive server access logs. If null and enable_access_logging = true, a companion log bucket is created."
  type        = string
  default     = null
}

variable "access_logging_retention_days" {
  description = "Days to retain server access logs in the module-managed companion log bucket before automatic expiration."
  type        = number
  default     = 90

  validation {
    condition     = var.access_logging_retention_days >= 1 && floor(var.access_logging_retention_days) == var.access_logging_retention_days
    error_message = "access_logging_retention_days must be a whole number >= 1."
  }
}

variable "enable_request_metrics" {
  description = "Enable CloudWatch S3 request metrics for the bucket (incurs CloudWatch custom metric charges; daily storage metrics are always enabled for free)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Governance & Tagging
# ------------------------------------------------------------------------------

variable "cost_center" {
  description = "Optional cost center or billing code applied as a tag to all resources."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all taggable resources created by this module."
  type        = map(string)
  default     = {}
}
