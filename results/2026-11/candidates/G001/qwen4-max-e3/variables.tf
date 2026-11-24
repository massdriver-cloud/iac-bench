# ---------------------------------------------------------------------------
# Required: the only thing an app team MUST decide.
# ---------------------------------------------------------------------------

variable "name" {
  description = <<-EOT
    Short name for your application's assets, e.g. "checkout-uploads" or
    "reports-generated". The module turns this into a globally-unique S3
    bucket name (a random suffix is appended), which you can read from the
    `bucket_name` output. Use lowercase letters, numbers and hyphens only,
    1-35 characters, starting and ending with a letter or number.
  EOT
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 35
    error_message = "name must be between 1 and 35 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must contain only lowercase letters, numbers and hyphens, and must start and end with a letter or number."
  }
}

# ---------------------------------------------------------------------------
# Optional: sensible, secure defaults for everything else.
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to the bucket (e.g. team, application, environment). Merged with the module's own management tags."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = <<-EOT
    Optional ARN of a customer-managed KMS key for encryption. Leave unset
    to use S3-managed AES256 encryption (fine for most application assets).
    When set, SSE-KMS is used with an S3 Bucket Key to keep KMS costs down.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:...:kms:...:key/...), or null."
  }
}

variable "versioning_enabled" {
  description = <<-EOT
    Keep previous versions of objects so accidental overwrites/deletes can
    be recovered. Enabled by default — strongly recommended. Old versions
    are automatically cleaned up after `noncurrent_version_expiration_days`
    so versioning does not grow costs without bound.
  EOT
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to retain superseded (noncurrent) object versions before deleting them. Only applies when versioning is enabled."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_multipart_upload_days" {
  description = <<-EOT
    Failed or abandoned multipart uploads silently accrue storage charges.
    The module always aborts them after this many days (7 by default).
  EOT
  type        = number
  default     = 7

  validation {
    condition     = var.abort_multipart_upload_days >= 1
    error_message = "abort_multipart_upload_days must be at least 1."
  }
}

variable "expiration_days" {
  description = <<-EOT
    Optional: permanently delete objects this many days after creation.
    Leave unset (default) for assets that should be kept indefinitely.
    Set this for short-lived data such as logs or scratch/generated files.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || var.expiration_days >= 1
    error_message = "expiration_days must be at least 1, or null."
  }
}

variable "transition_to_ia_days" {
  description = <<-EOT
    Optional: move objects to the cheaper Infrequent Access storage class
    this many days after creation (minimum 30, S3 requirement). Good for
    large media that is rarely read after its first weeks. Leave unset to
    keep everything in Standard.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.transition_to_ia_days == null || var.transition_to_ia_days >= 30
    error_message = "transition_to_ia_days must be at least 30 (S3 minimum for STANDARD_IA), or null."
  }
}

variable "cors_rules" {
  description = <<-EOT
    Optional CORS rules, needed only if browsers upload/download directly
    to this bucket (e.g. presigned-URL uploads from a web app). Example:

      cors_rules = [{
        allowed_methods = ["GET", "PUT"]
        allowed_origins = ["https://app.example.com"]
      }]
  EOT
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), ["*"])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.cors_rules :
      alltrue([for m in r.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    ])
    error_message = "cors_rules.allowed_methods may only contain GET, PUT, POST, DELETE or HEAD."
  }
}

variable "access_log_target_bucket" {
  description = <<-EOT
    Optional: name (id) of an existing bucket to receive S3 server access
    logs for this bucket. Leave unset unless your platform team has given
    you a central logging bucket.
  EOT
  type        = string
  default     = null
}

variable "access_log_target_prefix" {
  description = "Prefix for access log objects in the target bucket. Defaults to \"<name>/\"."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = <<-EOT
    Allow OpenTofu to delete the bucket even if it still contains objects.
    Keep this false (default) for anything you care about — it is your
    protection against accidental data loss. Enable only for disposable
    dev/test buckets.
  EOT
  type        = bool
  default     = false
}
