# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Name of the bucket. Your application will use this to address its assets.

    Bucket names must be globally unique across ALL of AWS (every account,
    every region), so pick something with your team/app in it, e.g.
    "acme-billing-web-prod-assets". Lowercase letters, numbers, dots and
    hyphens only, 3-63 characters.
  EOT

  validation {
    condition = (
      length(var.name) >= 3
      && length(var.name) <= 63
      && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.name))
      && !can(regex("[.][.]", var.name))
      && !can(regex("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", var.name))
      && !startswith(var.name, "xn--")
    )
    error_message = "Invalid bucket name. Must be 3-63 characters of lowercase letters, numbers, dots and hyphens; start and end with a letter or number; contain no consecutive dots; not look like an IP address; and not start with \"xn--\"."
  }
}

# ---------------------------------------------------------------------------
# Optional — sensible defaults, override only when you know why
# ---------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the bucket. Recommended: team, app, env. Defaults to none."
  default     = {}
}

variable "versioning_enabled" {
  type        = bool
  description = "Keep old versions of objects when they are overwritten or deleted, so mistakes can be undone. Old versions are cleaned up automatically after `noncurrent_version_expiration_days`, so this doesn't grow the bill unbounded. Default: true."
  default     = true
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "How many days to keep superseded/deleted object versions before permanently removing them. Only matters when versioning is enabled. Default: 90."
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "object_expiration_days" {
  type        = number
  description = "Automatically delete every object this many days after it was written. Leave null (the default) to keep objects until your app deletes them. Only set this for disposable content such as logs or scratch files — never for user data."
  default     = null

  validation {
    condition     = var.object_expiration_days == null || var.object_expiration_days >= 1
    error_message = "object_expiration_days must be at least 1, or null to disable."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  description = "Incomplete multipart uploads sit invisibly in the bucket and cost money. The module aborts them after this many days. Default: 7."
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of a KMS key to encrypt the bucket with. Leave null (the default) to use S3-managed encryption (SSE-S3/AES256), which is free and needs no setup. Only bring your own KMS key if you have a concrete reason, e.g. compliance requirements or cross-account access."
  default     = null
}

variable "force_destroy" {
  type        = bool
  description = "Allow deleting the bucket even while it still contains objects (tofu destroy will empty it first). Dangerous for real data — intended for throwaway dev/sandbox buckets only. Default: false."
  default     = false
}

variable "access_logging" {
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  description = "Send S3 server access logs to another bucket, e.g. { target_bucket = \"acme-central-logs\" }. Null (the default) disables access logging. The target bucket must exist and must accept writes from the S3 log delivery group."
  default     = null
}

variable "cors_rules" {
  type = list(object({
    id              = optional(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), ["*"])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  description = "CORS rules, needed only if browsers talk to the bucket directly (e.g. uploading files straight from a web app via presigned URLs). Empty by default, which means no cross-origin access."
  default     = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      alltrue([for m in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    ])
    error_message = "cors_rules allowed_methods may only contain GET, PUT, POST, DELETE and HEAD."
  }
}
