# -----------------------------------------------------------------------------
# Required inputs - the only two things an app team has to think about.
# -----------------------------------------------------------------------------

variable "application" {
  description = <<-EOT
    Short name of the application that owns this bucket, e.g. "photo-service".
    Lowercase letters, digits and hyphens only; 2-24 characters. It becomes part
    of the bucket name, so it cannot be changed later without replacing the bucket.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.application))
    error_message = "application must be 2-24 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment environment this bucket belongs to, e.g. "dev", "staging", "prod".
    Lowercase letters and digits only; 2-10 characters. Becomes part of the bucket name.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or digits (e.g. dev, staging, prod)."
  }
}

# -----------------------------------------------------------------------------
# Optional inputs - sensible defaults; override only if you know you need to.
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region to create the bucket in. Defaults to the region configured in the environment (AWS_REGION / AWS_DEFAULT_REGION / profile)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags to apply to everything the module creates. The module always adds Application, Environment and ManagedBy."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = <<-EOT
    ARN of a customer-managed KMS key to encrypt objects with (SSE-KMS, with S3 Bucket Keys
    enabled to keep KMS costs down). Leave null to use S3-managed encryption (SSE-S3 / AES-256),
    which is fully encrypted at rest and right for the vast majority of application assets.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias or key id."
  }
}

variable "noncurrent_version_retention_days" {
  description = <<-EOT
    Versioning is always on so that overwritten or deleted objects can be recovered. This is how
    many days old (non-current) versions are kept before S3 permanently removes them.
    Raise it for data you may need to roll back further; it does not affect current objects.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number of days >= 1."
  }
}

variable "expire_objects_after_days" {
  description = <<-EOT
    If set, current objects are permanently deleted this many days after they were created.
    Leave null (the default) for assets that must live indefinitely, such as user uploads.
    Set it for disposable data such as logs, exports or generated reports (e.g. 90).
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null || (try(var.expire_objects_after_days >= 1, false) && try(floor(var.expire_objects_after_days) == var.expire_objects_after_days, false))
    error_message = "expire_objects_after_days must be null or a whole number of days >= 1."
  }
}

variable "intelligent_tiering" {
  description = <<-EOT
    Automatically move objects to the S3 Intelligent-Tiering storage class so that rarely-read
    assets (old uploads, archived media) cost less without any change to how they are accessed.
    Recommended for assets with unpredictable access patterns. Set to false for buckets that hold
    only short-lived or tiny objects, where the small per-object monitoring fee is not worth it.
  EOT
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = <<-EOT
    Browser origins allowed to talk to the bucket directly (e.g. for pre-signed browser uploads
    or serving images to a web app), such as ["https://app.example.com"]. Leave empty if your
    application only accesses the bucket from the server side. Wildcards such as
    "https://*.example.com" are allowed; a bare "*" is not.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https?://", o))])
    error_message = "Every CORS origin must be a full origin starting with http:// or https:// (a bare \"*\" is not permitted)."
  }
}

variable "access_log_bucket_name" {
  description = <<-EOT
    Name of an existing S3 bucket to deliver server access logs to. Leave null to disable
    access logging. Logs are written under the prefix "<this bucket name>/".
  EOT
  type        = string
  default     = null
}

variable "create_access_policies" {
  description = <<-EOT
    Create two IAM managed policies - one read-write, one read-only - scoped to this bucket, so
    that application roles can be granted access by attaching a policy instead of hand-writing
    S3 IAM statements. Their ARNs are exposed as outputs.
  EOT
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = <<-EOT
    Allow `tofu destroy` to delete the bucket even when it still contains objects. Keep false
    (the default) anywhere data matters; true is only appropriate for throwaway environments.
  EOT
  type        = bool
  default     = false
}
