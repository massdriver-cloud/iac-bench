# ---------------------------------------------------------------------------
# Required — the one thing every team must decide
# ---------------------------------------------------------------------------

variable "bucket_name" {
  description = <<-EOT
    Globally-unique name for the bucket. Identify your app and environment,
    e.g. "acme-payments-assets-prod". S3 naming rules apply: 3-63 characters
    of lowercase letters, numbers, dots and hyphens; start and end with a
    letter or number; must not look like an IP address.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, numbers, dots and hyphens, starting and ending with a letter or number."
  }

  validation {
    condition     = !can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.bucket_name))
    error_message = "bucket_name must not be formatted as an IP address."
  }

  validation {
    condition     = !can(regex("\\.\\.|\\.-|-\\.", var.bucket_name))
    error_message = "bucket_name must not contain two adjacent periods or a hyphen next to a period."
  }

  validation {
    condition     = !startswith(var.bucket_name, "xn--") && !startswith(var.bucket_name, "sthree-") && !startswith(var.bucket_name, "amzn-s3-demo-")
    error_message = "bucket_name must not start with a reserved prefix (xn--, sthree-, amzn-s3-demo-)."
  }

  validation {
    condition     = !endswith(var.bucket_name, "-s3alias") && !endswith(var.bucket_name, "--ol-s3") && !endswith(var.bucket_name, ".mrap") && !endswith(var.bucket_name, "--x-s3") && !endswith(var.bucket_name, "--table-s3")
    error_message = "bucket_name must not end with a reserved suffix (-s3alias, --ol-s3, .mrap, --x-s3, --table-s3)."
  }
}

variable "tags" {
  description = "Tags added to the bucket on top of the module's own (e.g. team, service, cost-center)."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Optional knobs — sensible defaults, most teams never touch these
# ---------------------------------------------------------------------------

variable "enable_versioning" {
  description = "Keep old versions when objects are overwritten or deleted, so accidents are recoverable. Turn off only for regenerable throwaway data."
  type        = bool
  default     = true
  nullable    = false
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete the bucket even while it still contains objects. Dangerous — only for short-lived dev/test buckets."
  type        = bool
  default     = false
  nullable    = false
}

variable "expiration_days" {
  description = "Automatically delete objects this many days after upload (e.g. 365 for a logs bucket). 0 keeps objects forever."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.expiration_days >= 0
    error_message = "expiration_days must be 0 (keep objects forever) or a positive number of days."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent object versions this many days after they were superseded, so old versions don't silently cost money. Only relevant when versioning is on."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Abort and clean up unfinished multipart uploads after this many days. Failed uploads otherwise sit in the bucket costing money forever."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}

# ---------------------------------------------------------------------------
# Advanced — only if you already know you need them
# ---------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "Full ARN of a customer-managed KMS key used to encrypt the bucket. Leave null for SSE-S3 (AES256), which needs no key management and is the right default for most teams."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:\\d{12}:key\\/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (e.g. arn:aws:kms:eu-west-1:123456789012:key/abcd1234-...), or null."
  }
}

variable "cors_allowed_origins" {
  description = "Origins allowed to talk to the bucket from a browser, e.g. [\"https://app.acme.com\"] for direct browser uploads. Empty means no CORS, which is correct when only your servers touch the bucket."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for origin in var.cors_allowed_origins : can(regex("^https?://", origin))])
    error_message = "Every CORS origin must start with http:// or https://."
  }
}

variable "logging_target_bucket" {
  description = "Name of an existing bucket that should receive this bucket's server access logs (objects are prefixed with this bucket's name). Null disables access logging."
  type        = string
  default     = null
}

variable "extra_bucket_policy_json" {
  description = "Extra bucket policy statements (a JSON policy document, e.g. from an aws_iam_policy_document data source) merged on top of the module's own policy — for granting a CDN or another account access. The module's guardrails always apply."
  type        = string
  default     = null

  validation {
    condition     = var.extra_bucket_policy_json == null || can(jsondecode(var.extra_bucket_policy_json))
    error_message = "extra_bucket_policy_json must be valid JSON, or null."
  }
}
