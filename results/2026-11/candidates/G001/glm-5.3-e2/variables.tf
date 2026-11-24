# ---------------------------------------------------------------------------
# Inputs
#
# Only `name` and `environment` are required. Everything else has a safe
# default chosen by this module; override only what you actually need.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Short name of the application or kind of assets this bucket holds, e.g. \"user-uploads\", \"media\", \"exports\", \"logs\". Used as the first part of the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-30 characters, using only lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment the bucket belongs to, e.g. \"dev\", \"staging\", \"prod\". Used in the bucket name and as a tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,10}$", var.environment))
    error_message = "The environment must be 1-11 characters, using only lowercase letters, digits and hyphens, and must start with a letter or digit."
  }
}

variable "aws_region" {
  description = "AWS region the bucket is created in. S3 bucket names are global but buckets live in one region; set this to the region your application runs in."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "The aws_region must be a valid AWS region name, e.g. \"eu-west-1\"."
  }
}

variable "bucket_name" {
  description = "Full bucket name override for the rare cases where a specific name is required. Leave unset to use the module's generated, collision-free name: <name>-<environment>-<aws account id>."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "The bucket_name override must be 3-63 characters, using only lowercase letters, digits and hyphens (no dots), and must start and end with a letter or digit."
  }
}

variable "tags" {
  description = "Additional tags for the bucket and any KMS key the module creates, e.g. { Team = \"payments\" }. These override the module's baseline tags on conflict."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Keep every version of every object, protecting against accidental overwrites and deletes. Old (noncurrent) versions are cleaned up automatically; see expire_noncurrent_versions_after_days. Cannot be disabled while object_lock is set."
  type        = bool
  default     = true
}

variable "encryption" {
  description = "Server-side encryption at rest: \"aws:s3\" (SSE-S3, the default - no cost, nothing to manage) or \"aws:kms\" (customer-managed KMS key, see kms_key_arn)."
  type        = string
  default     = "aws:s3"

  validation {
    condition     = contains(["aws:s3", "aws:kms"], var.encryption)
    error_message = "The encryption must be either \"aws:s3\" or \"aws:kms\"."
  }
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use when encryption = \"aws:kms\". Leave unset and the module creates and manages a dedicated, automatically rotated key (aliased after the bucket) for this bucket instead. If you bring your own key, the principals in read_only_principals / read_write_principals must also be allowed to use that key in its key policy."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:[^:]+:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be the ARN of a KMS key (it starts with \"arn:\" and contains \":kms:\")."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period before a module-created KMS key is permanently destroyed after it disappears from the configuration. Longer windows leave more time to notice and recover from a mistake."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "The kms_key_deletion_window_in_days must be between 7 and 30 (an AWS limit)."
  }
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it still contains objects (all versions of them). Leave false in anything that has ever held real data: without it, a `tofu destroy` that would delete data fails instead."
  type        = bool
  default     = false
}

variable "read_write_principals" {
  description = "IAM role or user ARNs (e.g. your application's task or instance role) that are granted read/write access to the bucket via its bucket policy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_write_principals : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/.+$", arn))])
    error_message = "Each read_write_principals entry must be an IAM role or user ARN, e.g. \"arn:aws:iam::123456789012:role/my-app\"."
  }
}

variable "read_only_principals" {
  description = "IAM role or user ARNs that are granted read-only access to the bucket via its bucket policy (a subset of what read_write_principals gets)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_only_principals : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/.+$", arn))])
    error_message = "Each read_only_principals entry must be an IAM role or user ARN, e.g. \"arn:aws:iam::123456789012:role/my-app-readonly\"."
  }
}

variable "abort_incomplete_multipart_uploads_after_days" {
  description = "Clean up the parts of multipart uploads that were started but never completed after this many days. Those parts are invisible in object listings but cost storage money. Set to null to disable."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_uploads_after_days == null || var.abort_incomplete_multipart_uploads_after_days >= 1
    error_message = "The abort_incomplete_multipart_uploads_after_days must be at least 1, or null to disable."
  }
}

variable "expire_noncurrent_versions_after_days" {
  description = "Delete old (noncurrent) object versions this many days after they stop being current. This is what keeps versioning affordable. Set to null to keep every old version forever (not recommended)."
  type        = number
  default     = 90

  validation {
    condition     = var.expire_noncurrent_versions_after_days == null || var.expire_noncurrent_versions_after_days >= 1
    error_message = "The expire_noncurrent_versions_after_days must be at least 1, or null to disable."
  }
}

variable "expire_objects_after_days" {
  description = "Permanently delete objects this many days after they are uploaded, regardless of versioning. Leave unset to keep objects until they are deleted explicitly. Useful for temporary, scratch or log-type buckets."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || var.expire_objects_after_days >= 1
    error_message = "The expire_objects_after_days must be at least 1, or null to disable."
  }
}

variable "transition_to_standard_ia_after_days" {
  description = "Move objects to Standard-Infrequent Access storage (cheaper storage, higher per-request cost) this many days after upload. Leave unset to keep objects in Standard storage. Only worth it for data rarely read."
  type        = number
  default     = null

  validation {
    condition     = var.transition_to_standard_ia_after_days == null || var.transition_to_standard_ia_after_days >= 30
    error_message = "The transition_to_standard_ia_after_days must be at least 30 (an AWS minimum), or null to disable."
  }
}

variable "transition_to_glacier_instant_retrieval_after_days" {
  description = "Move objects to Glacier Instant Retrieval (much cheaper storage, millisecond access, higher per-request cost) this many days after upload. Leave unset to disable. Suits archives that are read occasionally."
  type        = number
  default     = null

  validation {
    condition     = var.transition_to_glacier_instant_retrieval_after_days == null || var.transition_to_glacier_instant_retrieval_after_days >= 1
    error_message = "The transition_to_glacier_instant_retrieval_after_days must be at least 1, or null to disable."
  }
}

variable "transition_to_deep_archive_after_days" {
  description = "Move objects to Deep Archive (the cheapest storage, hours to retrieve) this many days after upload. Leave unset to disable. Suits data kept only for compliance or rare recovery."
  type        = number
  default     = null

  validation {
    condition     = var.transition_to_deep_archive_after_days == null || var.transition_to_deep_archive_after_days >= 1
    error_message = "The transition_to_deep_archive_after_days must be at least 1, or null to disable."
  }
}

variable "cors_rules" {
  description = "CORS rules for browser access, e.g. for uploads directly from a web app. Example: [{ allowed_headers = [\"*\"], allowed_methods = [\"GET\", \"PUT\", \"POST\"], allowed_origins = [\"https://app.example.com\"] }]. expose_headers commonly needs [\"ETag\"] for browser multipart uploads."
  type = list(object({
    allowed_headers = optional(list(string))
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_methods) > 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)]) &&
      length(rule.allowed_origins) > 0 &&
      alltrue([for origin in rule.allowed_origins : length(origin) > 0])
    ])
    error_message = "Each cors_rules entry needs at least one allowed_methods entry (only GET, PUT, POST, DELETE, HEAD are valid) and at least one non-empty allowed_origins entry."
  }
}

variable "access_logging" {
  description = "Send S3 server access logs to an existing bucket, e.g. a shared logging bucket. The target bucket must be owned by the same account and must already allow the S3 log delivery service to write to it (see the module README)."
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  default = null

  validation {
    condition     = var.access_logging == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logging.target_bucket))
    error_message = "The access_logging.target_bucket must be the name of an existing S3 bucket."
  }
}

variable "object_lock" {
  description = "Enable S3 Object Lock (write-once-read-many retention) for regulatory or audit-grade immutability. null (default) = disabled. NOTE: enabling Object Lock is a one-way door - the bucket can never have it disabled again, and in COMPLIANCE mode nobody (not even an administrator) can delete an object before its retention expires. Set to {} for the safe defaults (GOVERNANCE mode, 30 days)."
  type = object({
    mode = optional(string, "GOVERNANCE")
    days = optional(number, 30)
  })
  default = null

  validation {
    condition     = var.object_lock == null || contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock.mode)
    error_message = "The object_lock.mode must be \"GOVERNANCE\" (privileged break-glass possible) or \"COMPLIANCE\" (nobody can shorten retention)."
  }

  validation {
    condition     = var.object_lock == null || (var.object_lock.days >= 1 && var.object_lock.days <= 36500)
    error_message = "The object_lock.days must be between 1 and 36500 (100 years)."
  }
}
