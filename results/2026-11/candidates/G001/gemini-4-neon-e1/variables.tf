################################################################################
# Required Inputs — the only values an application developer needs to provide
################################################################################

variable "application" {
  description = "Name of the application or service that owns this bucket (e.g., \"storefront\", \"billing-api\"). Used for deterministic bucket naming and resource tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.application)) && !strcontains(var.application, "--")
    error_message = "application must be 2–32 characters, lowercase alphanumeric with single hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment for this bucket (e.g., \"dev\", \"staging\", \"prod\"). Used for bucket naming and resource tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", var.environment)) && !strcontains(var.environment, "--")
    error_message = "environment must be 2–16 characters, lowercase alphanumeric with single hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "purpose" {
  description = "Short description of the assets stored in this bucket (e.g., \"user-uploads\", \"media\", \"exports\", \"logs\"). Used for bucket naming and resource tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.purpose)) && !strcontains(var.purpose, "--")
    error_message = "purpose must be 2–32 characters, lowercase alphanumeric with single hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

################################################################################
# Workload Profile & Lifecycle (all optional — safe defaults built in)
################################################################################

variable "workload_type" {
  description = <<-EOT
    Opinionated lifecycle and cost-optimization preset tailored to common application workloads:
    - "general"      (default): Intelligent-Tiering on, keep current objects indefinitely, transition old versions at 30d and expire at 90d.
    - "user-uploads":           Intelligent-Tiering on, keep current objects indefinitely, transition old versions at 30d and expire at 90d.
    - "media":                  Intelligent-Tiering on, expire old versions after 30 days, abort failed multipart uploads after 3 days.
    - "generated":              Expire generated files after 30 days, expire old versions after 14 days, no Intelligent-Tiering overhead.
    - "logs":                   Transition logs to Glacier Instant Retrieval after 30 days, expire after 365 days, expire old versions after 30 days.
    Any individual lifecycle variable below can override the selected preset.
  EOT
  type        = string
  default     = "general"

  validation {
    condition     = contains(["general", "user-uploads", "media", "generated", "logs"], var.workload_type)
    error_message = "workload_type must be one of: general, user-uploads, media, generated, logs."
  }
}

variable "enable_versioning" {
  description = "Enable S3 object versioning to protect against accidental overwrites and deletes. Strongly recommended to leave enabled."
  type        = bool
  default     = true
}

variable "enable_intelligent_tiering" {
  description = "Automatically move objects (>= 128 KB) into S3 Intelligent-Tiering to save on infrequent access without retrieval fees. When null, follows workload_type."
  type        = bool
  default     = null
}

variable "object_expiration_days" {
  description = "Automatically delete current objects after this many days. When null, follows workload_type (no automatic expiration for general, user-uploads, and media; 30 days for generated; 365 days for logs)."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be null or a positive integer."
  }
}

variable "archive_after_days" {
  description = "Transition current objects to Glacier Instant Retrieval after this many days (applies when Intelligent-Tiering is disabled). When null, follows workload_type (30 days for logs, disabled for others)."
  type        = number
  default     = null

  validation {
    condition     = var.archive_after_days == null || (var.archive_after_days >= 1 && floor(var.archive_after_days) == var.archive_after_days)
    error_message = "archive_after_days must be null or a positive integer."
  }
}

variable "noncurrent_version_transition_days" {
  description = "Move previous object versions to a cheaper storage class (STANDARD_IA when >= 30 days, GLACIER_IR when < 30 days) after this many days. When null, follows workload_type. Skipped automatically if >= noncurrent_version_expiration_days."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_transition_days == null || (var.noncurrent_version_transition_days >= 1 && floor(var.noncurrent_version_transition_days) == var.noncurrent_version_transition_days)
    error_message = "noncurrent_version_transition_days must be null or a positive integer."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Permanently delete previous object versions after this many days to prevent unbounded storage growth. When null, follows workload_type (90 days for general/user-uploads, 30 for media/logs, 14 for generated)."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null || (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be null or a positive integer."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Abort and clean up failed multipart uploads after this many days so orphaned chunks do not incur storage costs. When null, follows workload_type (3 days for media, 7 days for others)."
  type        = number
  default     = null

  validation {
    condition     = var.abort_incomplete_multipart_upload_days == null || (var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 90 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days)
    error_message = "abort_incomplete_multipart_upload_days must be null or an integer between 1 and 90."
  }
}

variable "additional_lifecycle_rules" {
  description = "Optional prefix-scoped lifecycle rules for advanced use cases (e.g., expiring only \"tmp/\" after 1 day)."
  type = list(object({
    id                         = string
    prefix                     = string
    expiration_days            = optional(number)
    noncurrent_expiration_days = optional(number)
    transition_days            = optional(number)
    transition_storage_class   = optional(string, "GLACIER_IR")
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.additional_lifecycle_rules :
      contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], r.transition_storage_class)
    ])
    error_message = "transition_storage_class must be a valid S3 storage class (STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER, DEEP_ARCHIVE)."
  }
}

################################################################################
# Security & Encryption
################################################################################

variable "encryption_type" {
  description = "Server-side encryption mode: \"kms\" (default — dedicated customer-managed KMS key with automatic rotation and S3 Bucket Keys) or \"sse-s3\" (AWS-managed AES256 encryption)."
  type        = string
  default     = "kms"

  validation {
    condition     = contains(["kms", "sse-s3"], var.encryption_type)
    error_message = "encryption_type must be either \"kms\" or \"sse-s3\"."
  }
}

variable "kms_key_arn" {
  description = "Optional existing KMS key ARN to encrypt this bucket instead of creating a dedicated key. Only valid when encryption_type is \"kms\"."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-)?[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "kms_key_deletion_window_days" {
  description = "Waiting period (7–30 days) before a deleted customer-managed KMS key is permanently destroyed."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_days >= 7 && var.kms_key_deletion_window_days <= 30 && floor(var.kms_key_deletion_window_days) == var.kms_key_deletion_window_days
    error_message = "kms_key_deletion_window_days must be an integer between 7 and 30."
  }
}

variable "enforce_tls_1_2" {
  description = "In addition to blocking all non-HTTPS traffic, deny requests using TLS versions older than 1.2."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow OpenTofu to destroy the bucket even when it still contains objects. Keep false in production to prevent accidental data loss."
  type        = bool
  default     = false
}

variable "object_lock_enabled" {
  description = "Enable S3 Object Lock (WORM protection) for compliance or immutable audit logs. Cannot be disabled after bucket creation."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Default Object Lock retention mode when object_lock_enabled is true: \"GOVERNANCE\" or \"COMPLIANCE\"."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be either \"GOVERNANCE\" or \"COMPLIANCE\"."
  }
}

variable "object_lock_retention_days" {
  description = "Optional default Object Lock retention period in days. Only valid when object_lock_enabled is true."
  type        = number
  default     = null

  validation {
    condition     = var.object_lock_retention_days == null || (var.object_lock_retention_days >= 1 && floor(var.object_lock_retention_days) == var.object_lock_retention_days)
    error_message = "object_lock_retention_days must be null or a positive integer."
  }
}

################################################################################
# Access Control, Browser Uploads (CORS) & Integrations
################################################################################

variable "create_iam_policies" {
  description = "Create ready-to-attach least-privilege IAM policies (read-only, read-write, write-only) covering both S3 and KMS permissions so application roles do not hand-roll IAM policies."
  type        = bool
  default     = true
}

variable "read_only_principals" {
  description = "Optional list of IAM role, user, or account ARNs granted read-only access via the bucket policy (and KMS decrypt when using a module-managed KMS key)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.read_only_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))])
    error_message = "Every entry in read_only_principals must be a valid IAM role, user, or account root ARN."
  }
}

variable "read_write_principals" {
  description = "Optional list of IAM role, user, or account ARNs granted read-write access via the bucket policy (and KMS encrypt/decrypt when using a module-managed KMS key)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.read_write_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))])
    error_message = "Every entry in read_write_principals must be a valid IAM role, user, or account root ARN."
  }
}

variable "write_only_principals" {
  description = "Optional list of IAM role, user, or account ARNs granted write-only access (e.g., log shippers or upload workers) via the bucket policy and KMS key policy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.write_only_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", p))])
    error_message = "Every entry in write_only_principals must be a valid IAM role, user, or account root ARN."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional CloudFront distribution ARNs granted Origin Access Control (OAC) read access to this bucket and its KMS key. Use this instead of making media buckets public."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", a))])
    error_message = "Every entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

variable "cors_allowed_origins" {
  description = "Optional list of exact browser origins (e.g., [\"https://app.example.com\"]) allowed to upload or fetch assets via presigned URLs. Wildcard \"*\" is intentionally disallowed; leave empty to disable CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https?://[^\\s*]+$", o))])
    error_message = "Each CORS origin must be an explicit http:// or https:// origin without wildcards (e.g., \"https://app.example.com\")."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods permitted by CORS when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must contain one or more of: GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cors_allowed_headers" {
  description = "Request headers permitted by CORS when cors_allowed_origins is non-empty. Defaults to [\"*\"] so presigned S3 upload headers work cleanly with explicit allowed_origins."
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "Response headers exposed to browsers when cors_allowed_origins is non-empty. Includes ETag by default so browser multipart uploaders work out of the box."
  type        = list(string)
  default     = ["ETag", "x-amz-version-id", "x-amz-request-id"]
}

variable "cors_max_age_seconds" {
  description = "How long (in seconds) browsers may cache CORS preflight responses."
  type        = number
  default     = 3600

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "cors_max_age_seconds must be between 0 and 86400."
  }
}

variable "additional_bucket_policy_json" {
  description = "Optional additional IAM policy JSON merged into the bucket policy. The module's mandatory security Deny statements (TLS, encryption guardrails) always remain enforced."
  type        = string
  default     = null
}

variable "enable_eventbridge" {
  description = "Emit S3 object events (created, deleted, restored, tagged) to Amazon EventBridge so applications can trigger asynchronous processing pipelines (thumbnails, virus scans, transcoding)."
  type        = bool
  default     = false
}

################################################################################
# Observability & Access Logging
################################################################################

variable "enable_access_logging" {
  description = "Enable S3 Server Access Logging for auditability. If access_log_bucket_name is not supplied, the module creates and secures a dedicated companion access-logs bucket automatically."
  type        = bool
  default     = true
}

variable "access_log_bucket_name" {
  description = "Optional existing centralized S3 access log bucket name. When null and enable_access_logging is true, a dedicated companion log bucket is provisioned."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be null or a valid S3 bucket name."
  }
}

variable "access_log_prefix" {
  description = "Optional key prefix for server access logs in the target log bucket. Defaults to \"<bucket-name>/\"."
  type        = string
  default     = null
}

variable "access_log_retention_days" {
  description = "Number of days to retain server access logs in the companion access-logs bucket (only applies when the module creates the companion log bucket)."
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days >= 1 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "access_log_retention_days must be a positive integer."
  }
}

variable "enable_request_metrics" {
  description = "Enable 1-minute CloudWatch S3 request metrics (4xx/5xx errors, latency, bytes transferred) for the entire bucket."
  type        = bool
  default     = false
}

################################################################################
# Naming & Tagging
################################################################################

variable "bucket_name" {
  description = "Optional explicit S3 bucket name override. Leave null to use the module's deterministic globally unique naming convention (<application>-<environment>-<purpose>-<account_id>-<region>)."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name == null || (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "--") &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket_name))
    )
    error_message = "bucket_name must be 3–63 characters, lowercase alphanumeric with single hyphens, starting and ending with an alphanumeric character."
  }
}

variable "owner" {
  description = "Optional owning team name or email address added as the Owner tag."
  type        = string
  default     = null
}

variable "cost_center" {
  description = "Optional billing or cost-center identifier added as the CostCenter tag."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional additional tags merged onto all taggable resources created by this module."
  type        = map(string)
  default     = {}
}
