# ---------------------------------------------------------------------------
# The two inputs every team fills in
# ---------------------------------------------------------------------------

variable "name" {
  description = "Short name of the application that owns the assets, e.g. \"orders-api\". Becomes part of the bucket name and tags. Lowercase letters, digits and hyphens only; must start and end with a letter or digit."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "var.name must be 2-40 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit (e.g. \"orders-api\")."
  }
}

variable "environment" {
  description = "Deployment environment this bucket belongs to. Drives the bucket name and the destroy-protection defaults (buckets can only be force-destroyed outside prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "var.environment must be one of: \"dev\", \"staging\", \"prod\"."
  }
}

# ---------------------------------------------------------------------------
# Optional knobs — the defaults are right for almost every asset bucket
# ---------------------------------------------------------------------------

variable "versioning_enabled" {
  description = "Keep previous versions of every object. Recommended for asset buckets: it protects against accidental deletes and overwrites, and the module's lifecycle rules prune stale versions so storage cannot grow unbounded. Disabling this later suspends versioning; existing history is never lost."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow destroying the bucket even while it still contains objects. When left null the module decides: true for dev and staging (so throwaway environments can be torn down), false for prod (so production data is never destroyed by accident). Set this only if you have a specific reason to override that judgment."
  type        = bool
  default     = null
}

variable "retention" {
  description = <<-EOT
Optional lifecycle tuning, in days:
- expire_objects_after_days: permanently delete current objects older than N days. Use this for ephemeral assets (logs, generated files). Default: keep objects forever.
- expire_noncurrent_after_days: delete superseded object versions after N days. Only relevant while versioning is enabled. Default: 30.
- transition_to_ia_after_days: move current objects to STANDARD_IA storage after N days to save money on rarely-read assets. Must be smaller than expire_objects_after_days when both are set. Default: no transition.
EOT
  type = object({
    expire_objects_after_days    = optional(number)
    expire_noncurrent_after_days = optional(number, 30)
    transition_to_ia_after_days  = optional(number)
  })
  default = {}

  validation {
    condition = (
      (var.retention.expire_objects_after_days == null || var.retention.expire_objects_after_days > 0) &&
      (var.retention.transition_to_ia_after_days == null || var.retention.transition_to_ia_after_days > 0) &&
      var.retention.expire_noncurrent_after_days > 0
    )
    error_message = "Retention values must be positive numbers of days."
  }

  validation {
    condition = (
      var.retention.expire_objects_after_days == null ||
      var.retention.transition_to_ia_after_days == null ||
      var.retention.transition_to_ia_after_days < var.retention.expire_objects_after_days
    )
    error_message = "retention.transition_to_ia_after_days must be smaller than retention.expire_objects_after_days."
  }
}

variable "iam_role_arns" {
  description = "ARNs of the IAM roles your application runs as. The module attaches a least-privilege read/write policy for this bucket to each role, so you don't have to write any IAM yourself. Leave empty to manage access on your own (the policy document is still available as the app_access_policy_json output)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.iam_role_arns : can(regex("^arn:aws(-us-gov|-cn)?:iam::\\d{12}:role/.+$", arn))])
    error_message = "Every entry in var.iam_role_arns must be a valid IAM role ARN, e.g. arn:aws:iam::123456789012:role/orders-api."
  }
}

variable "tags" {
  description = "Extra tags for the bucket, merged on top of the module's standard tags (environment, application, managed-by)."
  type        = map(string)
  default     = {}
}
