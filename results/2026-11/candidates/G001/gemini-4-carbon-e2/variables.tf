# -----------------------------------------------------------------------------
# Required Inputs
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the owning application or service (lowercase letters, numbers, and single hyphens, e.g. \"checkout-api\")."
  type        = string

  validation {
    condition = (
      length(var.app_name) >= 2 &&
      length(var.app_name) <= 30 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.app_name)) &&
      !can(regex("--", var.app_name)) &&
      !startswith(var.app_name, "xn--") &&
      !startswith(var.app_name, "sthree-") &&
      !startswith(var.app_name, "amzn-s3-demo-")
    )
    error_message = "app_name must be 2-30 characters of lowercase letters, numbers, and single hyphens, must start and end with a letter or number, and must not use reserved S3 prefixes (xn--, sthree-, amzn-s3-demo-)."
  }
}

variable "environment" {
  description = "Deployment environment name (lowercase letters, numbers, and single hyphens, e.g. \"dev\", \"staging\", \"prod\")."
  type        = string

  validation {
    condition = (
      length(var.environment) >= 2 &&
      length(var.environment) <= 16 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.environment)) &&
      !can(regex("--", var.environment))
    )
    error_message = "environment must be 2-16 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number (e.g. \"dev\", \"staging\", \"prod\")."
  }
}

# -----------------------------------------------------------------------------
# Naming & Metadata
# -----------------------------------------------------------------------------

variable "purpose" {
  description = "Short label describing what this bucket stores (e.g. \"assets\", \"uploads\", \"videos\", \"exports\", \"logs\"). Allows one application to own multiple distinct buckets."
  type        = string
  default     = "assets"

  validation {
    condition = (
      length(var.purpose) >= 2 &&
      length(var.purpose) <= 20 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.purpose)) &&
      !can(regex("--", var.purpose))
    )
    error_message = "purpose must be 2-20 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit S3 bucket name. Leave null unless migrating an existing bucket; by default the module generates a globally unique, deterministic name including account ID and region."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name_override == null || (
      length(var.bucket_name_override) >= 3 &&
      length(var.bucket_name_override) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_override)) &&
      !startswith(var.bucket_name_override, "xn--") &&
      !startswith(var.bucket_name_override, "sthree-") &&
      !startswith(var.bucket_name_override, "amzn-s3-demo-") &&
      !endswith(var.bucket_name_override, "-s3alias") &&
      !endswith(var.bucket_name_override, "--ol-s3") &&
      !endswith(var.bucket_name_override, "-x-s3") &&
      !endswith(var.bucket_name_override, "--table-s3")
    )
    error_message = "bucket_name_override must be 3-63 characters using only lowercase letters, numbers, and hyphens (no dots, no reserved S3 prefixes or suffixes)."
  }
}

variable "tags" {
  description = "Additional AWS resource tags merged onto all taggable resources created by this module."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Data Protection, Lifecycle & Cost Controls
# -----------------------------------------------------------------------------

variable "versioning_enabled" {
  description = "Keep object version history to protect against accidental overwrites and deletions. Enabled by default."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow OpenTofu destroy to delete all objects and versions inside the bucket. Defaults to false; blocked in prod/production environments."
  type        = bool
  default     = false
}

variable "transition_to_intelligent_tiering_days" {
  description = "Days after creation before moving objects (>= 128 KB) to S3 Intelligent-Tiering for automatic storage cost savings. Set to null to keep objects in S3 Standard."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_to_intelligent_tiering_days == null || (var.transition_to_intelligent_tiering_days >= 0 && floor(var.transition_to_intelligent_tiering_days) == var.transition_to_intelligent_tiering_days)
    error_message = "transition_to_intelligent_tiering_days must be null or a non-negative integer."
  }
}

variable "object_expiration_days" {
  description = "Optional number of days after creation to automatically delete objects. Useful for temporary generated files, exports, or logs. Leave null (default) to retain objects indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be null or an integer >= 1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days after an object version becomes noncurrent (overwritten or deleted) before permanently deleting that historical version. Prevents unbounded version storage costs."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days == null || (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be null or an integer >= 1."
  }
}

variable "noncurrent_versions_to_retain" {
  description = "Optional count of newest noncurrent versions to retain even after noncurrent_version_expiration_days has elapsed. Set to null to expire all noncurrent versions past the retention window."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_versions_to_retain == null || (var.noncurrent_versions_to_retain >= 1 && var.noncurrent_versions_to_retain <= 100 && floor(var.noncurrent_versions_to_retain) == var.noncurrent_versions_to_retain)
    error_message = "noncurrent_versions_to_retain must be null or an integer between 1 and 100."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after initiation to automatically abort and clean up incomplete multipart uploads."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be an integer between 1 and 365."
  }
}

variable "prefix_lifecycle_rules" {
  description = "Optional per-prefix lifecycle rules (e.g. expire objects under \"tmp/\" after 1 day or \"exports/\" after 7 days while keeping \"uploads/\" indefinitely)."
  type = list(object({
    id                                 = string
    prefix                             = string
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transition_days                    = optional(number)
    transition_storage_class           = optional(string, "INTELLIGENT_TIERING")
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.prefix_lifecycle_rules :
      length(trimspace(r.id)) > 0 &&
      length(trimspace(r.prefix)) > 0 &&
      (r.expiration_days != null || r.noncurrent_version_expiration_days != null || r.transition_days != null) &&
      (r.expiration_days == null || r.expiration_days >= 1) &&
      (r.noncurrent_version_expiration_days == null || r.noncurrent_version_expiration_days >= 1) &&
      (r.transition_days == null || r.transition_days >= 0) &&
      contains(["INTELLIGENT_TIERING", "STANDARD_IA", "ONEZONE_IA", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], r.transition_storage_class)
    ])
    error_message = "Each prefix_lifecycle_rules entry must define a non-empty id and prefix, at least one lifecycle action (expiration_days, noncurrent_version_expiration_days, or transition_days), and a valid S3 storage class."
  }
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "create_kms_key" {
  description = "Create a dedicated customer-managed AWS KMS key (with automatic annual rotation and S3 Bucket Keys) for this bucket. When false and kms_key_arn is null, SSE-S3 (AES256) encryption is used."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of an existing customer-managed AWS KMS key to encrypt objects with SSE-KMS (with S3 Bucket Keys enabled). Mutually exclusive with create_kms_key = true."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z0-9]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a valid KMS key ARN (not an alias ARN)."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days (7-30) before a module-created KMS key is permanently deleted after destruction."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be an integer between 7 and 30."
  }
}

# -----------------------------------------------------------------------------
# Application Access, IAM & Integrations
# -----------------------------------------------------------------------------

variable "create_iam_policies" {
  description = "Create ready-to-attach least-privilege IAM managed policies (read-only and read-write, including KMS permissions when applicable) for application workloads."
  type        = bool
  default     = true
}

variable "read_write_iam_role_names" {
  description = "Optional set of IAM role names (e.g. ECS task roles, EKS Pod Identity / IRSA roles, Lambda execution roles) to automatically attach the bucket's read-write IAM policy to."
  type        = set(string)
  default     = []
}

variable "read_only_iam_role_names" {
  description = "Optional set of IAM role names to automatically attach the bucket's read-only IAM policy to."
  type        = set(string)
  default     = []
}

variable "read_write_principal_arns" {
  description = "Optional set of IAM principal ARNs granted read-write access directly in the bucket policy (and module-created KMS key policy). Useful for cross-account access."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_write_principal_arns : can(regex("^arn:aws(-[a-z0-9]+)?:iam::[0-9]{12}:(root|role/.+|user/.+)$", arn))])
    error_message = "Each entry in read_write_principal_arns must be a valid IAM role, user, or account root ARN."
  }
}

variable "read_only_principal_arns" {
  description = "Optional set of IAM principal ARNs granted read-only access directly in the bucket policy (and module-created KMS key policy)."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_only_principal_arns : can(regex("^arn:aws(-[a-z0-9]+)?:iam::[0-9]{12}:(root|role/.+|user/.+)$", arn))])
    error_message = "Each entry in read_only_principal_arns must be a valid IAM role, user, or account root ARN."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional set of CloudFront distribution ARNs allowed to read objects via Origin Access Control (OAC) while keeping the bucket completely private."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudfront_distribution_arns : can(regex("^arn:aws(-[a-z0-9]+)?:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))])
    error_message = "Each entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-based presigned uploads or direct asset fetches. Wildcard origins (\"*\") are disallowed when write methods (PUT, POST, DELETE) are enabled."
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
      for r in var.cors_rules :
      length(r.allowed_origins) > 0 &&
      length(r.allowed_methods) > 0 &&
      alltrue([for m in r.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)]) &&
      !(contains(r.allowed_origins, "*") && anytrue([for m in r.allowed_methods : contains(["PUT", "POST", "DELETE"], m)]))
    ])
    error_message = "Each CORS rule must specify valid HTTP methods (GET, HEAD, PUT, POST, DELETE) and at least one origin. Wildcard origin \"*\" is not permitted alongside write methods (PUT, POST, DELETE); specify explicit application origins instead."
  }
}

variable "enable_eventbridge" {
  description = "Forward bucket object events (uploads, deletions, restores) to Amazon EventBridge for asynchronous processing (e.g. image resizing, video transcoding, virus scanning)."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Logging & Audit
# -----------------------------------------------------------------------------

variable "access_log_bucket_name" {
  description = "Optional name of a centralized S3 access-logging bucket to deliver server access logs to."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Optional key prefix for server access logs delivered to access_log_bucket_name. Defaults to \"<bucket_name>/\"."
  type        = string
  default     = null
}

variable "allow_aws_log_delivery" {
  description = "Allow AWS log delivery service (delivery.logs.amazonaws.com) from this AWS account to write logs into this bucket (enable when purpose is storing ALB/NLB/VPC/WAF logs)."
  type        = bool
  default     = false
}
