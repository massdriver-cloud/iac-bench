# -----------------------------------------------------------------------------
# The two decisions only you can make: who owns the bucket, and for which
# environment. Everything else in this module has a deliberate, safe default.
# -----------------------------------------------------------------------------

variable "application" {
  type        = string
  description = "Name of the application these assets belong to, e.g. \"photo-service\". Used in the bucket name, IAM policy name, and tags. Must be 1-16 characters of lowercase letters, digits, and hyphens, starting and ending with a letter or digit."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.application))
    error_message = "application must be 1-16 characters of lowercase letters, digits, and hyphens, and must start and end with a letter or digit (e.g. \"photo-service\")."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment this bucket serves, e.g. \"prod\". Restricted to a fixed vocabulary so bucket names stay predictable across the organisation."

  validation {
    condition     = contains(["dev", "test", "qa", "uat", "staging", "prod", "shared", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, test, qa, uat, staging, prod, shared, sandbox."
  }
}

# -----------------------------------------------------------------------------
# Optional knobs. You almost certainly do not need any of these; the defaults
# are the right answer for the overwhelming majority of application buckets.
# -----------------------------------------------------------------------------

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Keep previous versions of objects. This is your undo button for accidental deletes and overwrites. Leave it on unless the bucket only ever holds disposable data."
}

variable "noncurrent_version_retention_days" {
  type        = number
  default     = 30
  description = "How long (in days) overwritten and deleted object versions stay recoverable before they are pruned automatically. Applies only when versioning is enabled."

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "object_expiration_days" {
  type        = number
  default     = null
  description = "If set, current objects are permanently deleted this many days after they are uploaded. Use for buckets holding transient data (build artifacts, caches, short-lived exports). Leave null to keep objects forever - the right default for most asset buckets."

  validation {
    condition     = var.object_expiration_days == null || var.object_expiration_days >= 1
    error_message = "object_expiration_days must be at least 1, or null to keep objects forever."
  }
}

variable "allow_public_access" {
  type        = bool
  default     = false
  description = "Removes every S3 public-access guard from the bucket. Almost never what you want: serve public content through a CDN or your application instead. Set true only if the bucket itself must be anonymously readable, and get a security review first."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of a customer-managed KMS key to encrypt objects with. Leave null to use S3-managed keys (SSE-S3): fully encrypted, zero setup. If you set this, your KMS key policy must allow the S3 service and your application principals to use the key."

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:[a-z0-9-]+:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, e.g. arn:aws:kms:us-east-1:123456789012:key/abc-123, or null."
  }
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = []
  description = "Browser origins allowed to call S3 directly, e.g. [\"https://app.example.com\"]. Only needed if browser JavaScript talks to S3 itself; uploads through your backend (including presigned URLs issued by your backend) do not need CORS. Leave empty by default."

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : o == "*" || can(regex("^https?://[^/]+$", o))])
    error_message = "Each entry in cors_allowed_origins must be \"*\" or a full origin like https://app.example.com (scheme and host only, no trailing slash or path)."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow the bucket to be destroyed even if it still contains objects. Default false, so a destroy fails loudly instead of silently throwing data away. Set true for throwaway environments."
}

variable "create_app_policy" {
  type        = bool
  default     = true
  description = "Create the standard read/write IAM policy for this bucket (exposed as the app_policy_arn output). Attach it to the IAM role your application runs as."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags, merged on top of the module's standard tags (Application, Environment, ManagedBy)."
}
