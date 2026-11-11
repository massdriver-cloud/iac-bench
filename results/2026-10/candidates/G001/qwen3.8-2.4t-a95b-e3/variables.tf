# -----------------------------------------------------------------------------
# The inputs an application team is expected to fill in
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Short name of the application or asset set this bucket belongs to, e.g. "invoice-service" or "user-uploads".
    It becomes part of the generated globally-unique bucket name: <name>-<environment>-<account-id>-<region>.
    Must be 2-24 characters of lower-case letters, numbers and hyphens, starting and ending with a letter or number.
  EOT

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 24 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "var.name must be 2-24 characters of lower-case letters, numbers and hyphens, starting and ending with a letter or number (e.g. \"invoice-service\")."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment this bucket belongs to, e.g. \"dev\", \"staging\" or \"prod\". Becomes part of the bucket name."
  default     = "dev"

  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 10 && can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "var.environment must be 2-10 characters of lower-case letters, numbers and hyphens (e.g. \"dev\", \"staging\", \"prod\")."
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags to apply to the bucket, in addition to the module's standard tags (Application, Environment, ManagedBy, Module). Tags you supply override the module's defaults."
  default     = {}
}

# -----------------------------------------------------------------------------
# Knobs that occasionally need turning. The defaults are the recommended setup.
# -----------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "AWS region to create the bucket in. Defaults to the ambient AWS_REGION from the environment."
  default     = null
}

variable "versioning_enabled" {
  type        = bool
  description = "Keep previous versions of overwritten or deleted objects. Recommended; it is the undo button for accidental data loss. Old versions are automatically pruned after 30 days."
  default     = true
}

variable "object_expiration_days" {
  type        = number
  description = "Automatically delete objects this many days after they are created. Leave unset (the default) to keep objects forever. Sensible for log, scratch and generated-file buckets."
  default     = null

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "var.object_expiration_days must be a whole number of days (1 or more), or left unset."
  }
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Browser origins (e.g. [\"https://app.example.com\"]) allowed to read from and upload to this bucket via CORS. Empty (the default) means no browser access is configured; your backend should use signed URLs or the AWS SDK instead."
  default     = []
}

variable "access_log_bucket" {
  type        = string
  description = "Name of an existing bucket that should receive this bucket's server access logs (that bucket must be configured to accept S3 log delivery). Leave unset to skip access logging."
  default     = null
}

variable "force_destroy" {
  type        = bool
  description = "Allow destroying the bucket even if it still contains objects. Convenient for throw-away dev buckets; keep false (the default) for anything you care about."
  default     = false
}
